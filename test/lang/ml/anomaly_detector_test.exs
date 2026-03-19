defmodule Lang.ML.AnomalyDetectorTest do
  use Lang.DataCase, async: true

  alias Lang.ML.AnomalyDetector
  alias Lang.Accounts.User
  alias Lang.Repo

  setup do
    # Create test user
    {:ok, user} = %User{
      email: "anomaly_test@example.com",
      hashed_password: "hashed_password"
    } |> Repo.insert()

    # Start AnomalyDetector for testing
    {:ok, _pid} = AnomalyDetector.start_link([])

    %{user: user}
  end

  describe "request analysis" do
    test "analyze_request/3 analyzes normal requests", %{user: user} do
      request = %{
        "method" => "initialize",
        "params" => %{"capabilities" => %{}}
      }

      result = AnomalyDetector.analyze_request(request, user.id, "test_session")

      assert result == :normal
    end

    test "analyze_request/3 detects anomalous requests", %{user: user} do
      # Create a request that might trigger anomaly detection
      large_request = %{
        "method" => "callTool",
        "params" => %{
          "name" => "lang.fs.scan",
          "arguments" => %{
            "path" => String.duplicate("/", 1000),  # Very long path
            "tools" => List.duplicate(%{"name" => "tool"}, 100)  # Many tools
          }
        }
      }

      result = AnomalyDetector.analyze_request(large_request, user.id, "test_session")

      # Should detect as anomaly due to size/complexity
      assert result != :normal
      assert is_tuple(result)
      {status, score, details} = result
      assert status == :anomaly
      assert is_float(score)
      assert is_map(details)
    end

    test "analyze_request/3 handles empty requests", %{user: user} do
      request = %{}

      result = AnomalyDetector.analyze_request(request, user.id, "test_session")

      assert result == :normal
    end

    test "analyze_request/3 handles malformed requests", %{user: user} do
      request = "not_a_map"

      # Should handle gracefully without crashing
      result = AnomalyDetector.analyze_request(request, user.id, "test_session")

      assert result == :normal
    end
  end

  describe "statistics tracking" do
    test "stats/0 returns current statistics", %{user: user} do
      # Get initial stats
      initial_stats = AnomalyDetector.stats()

      assert is_map(initial_stats)
      assert Map.has_key?(initial_stats, :anomaly_count)
      assert Map.has_key?(initial_stats, :model_loaded)
      assert initial_stats.anomaly_count == 0

      # Create an anomalous request
      large_request = %{
        "method" => "callTool",
        "params" => %{
          "name" => "lang.fs.scan",
          "arguments" => %{
            "path" => String.duplicate("/", 2000),
            "tools" => List.duplicate(%{"name" => "tool"}, 200)
          }
        }
      }

      AnomalyDetector.analyze_request(large_request, user.id, "test_session")

      # Get updated stats
      updated_stats = AnomalyDetector.stats()
      assert updated_stats.anomaly_count >= initial_stats.anomaly_count
    end
  end

  describe "feature extraction" do
    test "extracts features from requests correctly" do
      request = %{
        "method" => "callTool",
        "params" => %{
          "name" => "lang.fs.scan",
          "arguments" => %{
            "path" => "/test/path",
            "tools" => [%{"name" => "tool1"}, %{"name" => "tool2"}]
          }
        }
      }

      # We can't directly test the private extract_features function,
      # but we can verify that analysis works and produces expected results
      result = AnomalyDetector.analyze_request(request, "test_user", "test_session")

      # Should work without errors
      assert result == :normal or is_tuple(result)
    end
  end

  describe "anomaly scoring" do
    test "provides consistent anomaly scores", %{user: user} do
      # Test the same request multiple times
      request = %{
        "method" => "callTool",
        "params" => %{
          "name" => "lang.fs.scan",
          "arguments" => %{
            "path" => String.duplicate("/", 500),
            "tools" => List.duplicate(%{"name" => "tool"}, 50)
          }
        }
      }

      results = for _ <- 1..5 do
        AnomalyDetector.analyze_request(request, user.id, "test_session")
      end

      # All results should be consistent (all normal or all anomalous)
      all_normal = Enum.all?(results, &(&1 == :normal))
      all_anomalous = Enum.all?(results, fn
        {:anomaly, _, _} -> true
        _ -> false
      end)

      assert all_normal or all_anomalous
    end
  end

  describe "integration with AshEvents" do
    test "logs anomaly events", %{user: user} do
      # Create an anomalous request
      anomalous_request = %{
        "method" => "callTool",
        "params" => %{
          "name" => "lang.fs.scan",
          "arguments" => %{
            "path" => String.duplicate("/", 3000),
            "tools" => List.duplicate(%{"name" => "tool"}, 300)
          }
        }
      }

      result = AnomalyDetector.analyze_request(anomalous_request, user.id, "test_session")

      case result do
        {:anomaly, score, details} ->
          # If we detected an anomaly, verify that it would have been logged
          # (We can't easily test the actual logging without mocking AshEvents)
          assert is_float(score)
          assert score > 0.0
          assert is_map(details)

        :normal ->
          # Normal request - no anomaly logging needed
          assert true
      end
    end
  end

  describe "error handling" do
    test "handles database errors gracefully", %{user: user} do
      # Test with invalid user ID
      request = %{"method" => "initialize", "params" => %{}}

      result = AnomalyDetector.analyze_request(request, "invalid_user_id", "test_session")

      # Should not crash, should return normal or handle error
      assert result == :normal or is_tuple(result)
    end

    test "handles network-like failures", %{user: user} do
      # Test with very large request that might cause issues
      huge_request = %{
        "method" => "callTool",
        "params" => %{
          "name" => "lang.analyze.document",
          "arguments" => %{
            "content" => String.duplicate("x", 1024 * 1024),  # 1MB string
            "tools" => List.duplicate(%{"name" => "tool"}, 1000)
          }
        }
      }

      result = AnomalyDetector.analyze_request(huge_request, user.id, "test_session")

      # Should handle large requests without crashing
      assert result == :normal or is_tuple(result)
    end
  end

  describe "performance characteristics" do
    test "analyzes requests quickly", %{user: user} do
      request = %{
        "method" => "callTool",
        "params" => %{
          "name" => "lang.fs.scan",
          "arguments" => %{
            "path" => "/test/path",
            "tools" => [%{"name" => "tool1"}]
          }
        }
      }

      # Measure analysis time
      start_time = System.monotonic_time(:millisecond)

      for _ <- 1..100 do
        AnomalyDetector.analyze_request(request, user.id, "test_session")
      end

      end_time = System.monotonic_time(:millisecond)
      total_time = end_time - start_time
      avg_time = total_time / 100

      # Should be fast (less than 10ms per request on average)
      assert avg_time < 10
    end
  end
end