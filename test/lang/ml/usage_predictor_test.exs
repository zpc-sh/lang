defmodule Lang.ML.UsagePredictorTest do
  use Lang.DataCase, async: true

  alias Lang.ML.UsagePredictor
  alias Lang.Accounts.User
  alias Lang.Repo

  setup do
    # Create test user
    {:ok, user} = %User{
      email: "usage_test@example.com",
      hashed_password: "hashed_password"
    } |> Repo.insert()

    # Start UsagePredictor for testing
    {:ok, _pid} = UsagePredictor.start_link([])

    %{user: user}
  end

  describe "usage prediction" do
    test "predict_usage/2 predicts usage for different time windows", %{user: user} do
      # Record some usage data first
      usage_data = %{
        request_count: 10,
        tools_used: ["lang.fs.scan", "lang.analyze.document"],
        avg_response_time: 150,
        session_duration: 300
      }

      UsagePredictor.record_usage(user.id, usage_data)

      # Predict usage for different time windows
      prediction_hour = UsagePredictor.predict_usage(user.id, :hour)
      prediction_day = UsagePredictor.predict_usage(user.id, :day)
      prediction_week = UsagePredictor.predict_usage(user.id, :week)

      # Verify prediction structure
      assert is_map(prediction_hour)
      assert Map.has_key?(prediction_hour, :predicted_calls)
      assert Map.has_key?(prediction_hour, :confidence)
      assert Map.has_key?(prediction_hour, :time_window)
      assert Map.has_key?(prediction_hour, :recommendations)

      assert prediction_hour.time_window == :hour
      assert prediction_day.time_window == :day
      assert prediction_week.time_window == :week

      # Day prediction should be higher than hour
      assert prediction_day.predicted_calls >= prediction_hour.predicted_calls

      # Week prediction should be higher than day
      assert prediction_week.predicted_calls >= prediction_day.predicted_calls
    end

    test "predict_usage/2 uses default time window", %{user: user} do
      prediction = UsagePredictor.predict_usage(user.id)

      assert prediction.time_window == :hour
    end

    test "predict_usage/2 handles users with no usage data", %{user: user} do
      # Don't record any usage data

      prediction = UsagePredictor.predict_usage(user.id, :hour)

      # Should still return a prediction (using defaults)
      assert is_map(prediction)
      assert Map.has_key?(prediction, :predicted_calls)
      assert prediction.predicted_calls >= 0
    end
  end

  describe "usage data recording" do
    test "record_usage/2 stores usage data", %{user: user} do
      usage_data = %{
        request_count: 5,
        tools_used: ["lang.fs.scan"],
        avg_response_time: 200,
        session_duration: 180,
        error_count: 0
      }

      # Record usage
      :ok = UsagePredictor.record_usage(user.id, usage_data)

      # Verify data was recorded by checking stats
      stats = UsagePredictor.stats()
      assert stats.total_records >= 1
    end

    test "record_usage/2 handles multiple recordings", %{user: user} do
      # Record multiple usage events
      for i <- 1..5 do
        usage_data = %{
          request_count: i,
          tools_used: ["lang.fs.scan"],
          avg_response_time: 100 + i * 10,
          session_duration: 120 + i * 20
        }

        UsagePredictor.record_usage(user.id, usage_data)
      end

      stats = UsagePredictor.stats()
      assert stats.total_records >= 5
    end

    test "record_usage/2 handles empty usage data", %{user: user} do
      # Record empty usage data
      :ok = UsagePredictor.record_usage(user.id, %{})

      stats = UsagePredictor.stats()
      assert stats.total_records >= 1
    end
  end

  describe "statistics and monitoring" do
    test "stats/0 returns comprehensive statistics", %{user: user} do
      # Record some usage data
      UsagePredictor.record_usage(user.id, %{request_count: 10})
      UsagePredictor.record_usage(user.id, %{request_count: 20})

      stats = UsagePredictor.stats()

      assert is_map(stats)
      assert Map.has_key?(stats, :total_records)
      assert Map.has_key?(stats, :active_predictions)
      assert stats.total_records >= 2
      assert is_integer(stats.active_predictions)
    end

    test "stats/0 shows zero records initially" do
      stats = UsagePredictor.stats()

      assert stats.total_records == 0
      assert stats.active_predictions == 0
    end
  end

  describe "prediction accuracy over time" do
    test "predictions improve with more data", %{user: user} do
      # Record increasing usage patterns
      for i <- 1..10 do
        usage_data = %{
          request_count: i * 10,
          tools_used: ["lang.fs.scan", "lang.analyze.document"],
          avg_response_time: 100 + i * 5,
          session_duration: 200 + i * 10
        }

        UsagePredictor.record_usage(user.id, usage_data)

        # Make a prediction after each recording
        prediction = UsagePredictor.predict_usage(user.id, :hour)
        assert is_map(prediction)
        assert prediction.predicted_calls >= 0
      end

      # Final prediction should be reasonable
      final_prediction = UsagePredictor.predict_usage(user.id, :hour)
      assert final_prediction.predicted_calls > 0
      assert is_float(final_prediction.confidence)
      assert final_prediction.confidence >= 0.0
      assert final_prediction.confidence <= 1.0
    end
  end

  describe "recommendations generation" do
    test "generates appropriate recommendations", %{user: user} do
      # Record high usage data
      usage_data = %{
        request_count: 100,
        tools_used: ["lang.fs.scan", "lang.analyze.document", "lang.generate.code"],
        avg_response_time: 500,
        session_duration: 1800
      }

      UsagePredictor.record_usage(user.id, usage_data)

      prediction = UsagePredictor.predict_usage(user.id, :hour)

      # Should include recommendations
      assert is_list(prediction.recommendations)
      assert length(prediction.recommendations) > 0

      # Recommendations should be strings
      Enum.each(prediction.recommendations, fn rec ->
        assert is_binary(rec)
      end)
    end

    test "provides different recommendations based on usage patterns", %{user: user} do
      # Test with low usage
      low_usage = %{request_count: 1, avg_response_time: 50}
      UsagePredictor.record_usage(user.id, low_usage)
      low_prediction = UsagePredictor.predict_usage(user.id, :hour)

      # Test with high usage
      high_usage = %{request_count: 1000, avg_response_time: 2000}
      UsagePredictor.record_usage(user.id, high_usage)
      high_prediction = UsagePredictor.predict_usage(user.id, :hour)

      # Recommendations should differ
      assert low_prediction.recommendations != high_prediction.recommendations
    end
  end

  describe "error handling" do
    test "handles invalid user IDs gracefully", %{user: user} do
      # Test with invalid user ID
      prediction = UsagePredictor.predict_usage("invalid_user_id", :hour)

      # Should not crash, should return a prediction
      assert is_map(prediction)
      assert Map.has_key?(prediction, :predicted_calls)
    end

    test "handles malformed usage data", %{user: user} do
      # Record malformed data
      malformed_data = %{
        request_count: "not_a_number",
        tools_used: "not_a_list",
        invalid_field: "unexpected"
      }

      # Should not crash
      :ok = UsagePredictor.record_usage(user.id, malformed_data)

      # Should still be able to make predictions
      prediction = UsagePredictor.predict_usage(user.id, :hour)
      assert is_map(prediction)
    end

    test "handles very large datasets", %{user: user} do
      # Record a lot of usage data
      for i <- 1..1000 do
        usage_data = %{
          request_count: i,
          tools_used: ["tool_#{i}"],
          avg_response_time: 100 + i,
          session_duration: 200 + i
        }

        UsagePredictor.record_usage(user.id, usage_data)
      end

      # Should still work and make predictions
      prediction = UsagePredictor.predict_usage(user.id, :hour)
      assert is_map(prediction)
      assert prediction.predicted_calls >= 0
    end
  end

  describe "performance characteristics" do
    test "makes predictions quickly", %{user: user} do
      # Record some data
      UsagePredictor.record_usage(user.id, %{request_count: 10})

      # Measure prediction time
      start_time = System.monotonic_time(:microsecond)

      for _ <- 1..100 do
        UsagePredictor.predict_usage(user.id, :hour)
      end

      end_time = System.monotonic_time(:microsecond)
      total_time = end_time - start_time
      avg_time = total_time / 100

      # Should be fast (less than 1ms per prediction on average)
      assert avg_time < 1000
    end

    test "handles concurrent predictions", %{user: user} do
      # Record some data
      UsagePredictor.record_usage(user.id, %{request_count: 10})

      # Make concurrent predictions
      tasks = for _ <- 1..10 do
        Task.async(fn ->
          UsagePredictor.predict_usage(user.id, :hour)
        end)
      end

      # Wait for all tasks to complete
      results = Task.await_many(tasks, 5000)

      # All should succeed
      assert length(results) == 10
      Enum.each(results, fn result ->
        assert is_map(result)
        assert Map.has_key?(result, :predicted_calls)
      end)
    end
  end

  describe "data retention and cleanup" do
    test "maintains reasonable data size", %{user: user} do
      # Record a lot of data
      for i <- 1..2000 do
        UsagePredictor.record_usage(user.id, %{request_count: i})
      end

      # The system should automatically limit the data size
      stats = UsagePredictor.stats()

      # Should not grow indefinitely (implementation should limit to ~1000 records)
      assert stats.total_records <= 1100  # Allow some buffer
    end
  end
end