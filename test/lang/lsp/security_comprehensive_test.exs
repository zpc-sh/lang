defmodule Lang.LSP.SecurityComprehensiveTest do
  @moduledoc """
  Comprehensive security and race condition testing for LSP server.
  
  Tests defensive security measures, multi-client race conditions,
  MCP bridge security, and LSP method validation.
  """
  
  use ExUnit.Case, async: false
  
  alias Lang.LSP.{Server, Client, Dispatch}
  alias Lang.MCP.StreamBridge
  
  @moduletag :security
  @moduletag :integration
  
  setup_all do
    {:ok, _} = Application.ensure_all_started(:lang)
    :ok
  end
  
  describe "Client ID validation and security" do
    test "rejects invalid Client_ID formats" do
      invalid_ids = [
        "",
        "a",
        "short",
        "contains spaces",
        "contains@symbols",
        String.duplicate("a", 65),
        123,
        nil
      ]
      
      Enum.each(invalid_ids, fn invalid_id ->
        assert {:error, _} = StreamBridge.create_stream(
          "test_conn", 
          "test_user", 
          "test_session", 
          %{"client_id" => invalid_id}
        )
      end)
    end
    
    test "validates Client_ID authorization for MCP operations" do
      valid_client_id = "test_user_valid_client_123"
      invalid_client_id = "other_user_client_456"
      
      # Should succeed with proper client_id
      assert {:ok, _} = StreamBridge.create_stream(
        "test_conn",
        "test_user", 
        "test_session",
        %{"client_id" => valid_client_id}
      )
      
      # Should fail with unauthorized client_id
      assert {:error, {:client_id_invalid, _}} = StreamBridge.create_stream(
        "test_conn",
        "test_user",
        "test_session", 
        %{"client_id" => invalid_client_id}
      )
    end
    
    test "enforces rate limiting per Client_ID" do
      client_id = "test_rate_limit_client"
      
      # Simulate rapid requests that should trigger rate limiting
      requests = Enum.map(1..100, fn i ->
        Task.async(fn ->
          # Simulate LSP request with client identification
          message = %{
            "jsonrpc" => "2.0",
            "id" => i,
            "method" => "textDocument/completion",
            "params" => %{
              "textDocument" => %{"uri" => "file:///test.ex"},
              "position" => %{"line" => 0, "character" => 0}
            }
          }
          
          # This should trigger rate limiting after threshold
          GenServer.call(Server, {:lsp_request, client_id, message})
        end)
      end)
      
      results = Task.await_many(requests, 5000)
      
      # Some requests should be rate limited
      rate_limited = Enum.count(results, fn
        {:error, :rate_limited} -> true
        %{"error" => %{"code" => -32001}} -> true
        _ -> false
      end)
      
      assert rate_limited > 0, "Expected some requests to be rate limited"
    end
  end
  
  describe "Multi-client race condition testing" do  
    test "concurrent document modifications are handled safely" do
      host = (System.get_env("LSP_HOST") || "127.0.0.1") |> to_charlist()
      port = String.to_integer(System.get_env("LSP_PORT") || "4001") 
      shared_uri = "file:///tmp/race_condition_test.ex"
      
      # Create multiple clients that modify the same document
      clients = Enum.map(1..5, fn i ->
        Task.async(fn ->
          client_id = "race_client_#{i}_#{:erlang.unique_integer([:positive])}"
          {:ok, conn} = Client.connect(
            host: host, 
            port: port, 
            client_id: client_id,
            root_path: System.cwd!(),
            timeout: 5_000
          )
          
          # Each client opens the same document
          text = "defmodule RaceTest#{i} do\n  def test, do: #{i}\nend"
          :ok = notify_conn(conn, "textDocument/didOpen", %{
            "textDocument" => %{
              "uri" => shared_uri,
              "languageId" => "elixir", 
              "version" => 1,
              "text" => text
            }
          })
          
          # Rapid modifications
          Enum.each(1..10, fn v ->
            new_text = text <> "\n# Modification #{v} by client #{i}"
            :ok = notify_conn(conn, "textDocument/didChange", %{
              "textDocument" => %{"uri" => shared_uri, "version" => v + 1},
              "contentChanges" => [%{"text" => new_text}]
            })
          end)
          
          # Request completion to test read operations during writes
          result = Client.request_with_connection(conn, "textDocument/completion", %{
            "textDocument" => %{"uri" => shared_uri},
            "position" => %{"line" => 1, "character" => 10}
          }, timeout: 3_000)
          
          Client.disconnect(conn)
          result
        end)
      end)
      
      results = Task.await_many(clients, 10_000)
      
      # All clients should complete without crashes
      Enum.each(results, fn result ->
        assert match?({:ok, _}, result) or match?({:error, :timeout}, result),
               "Client should complete successfully or timeout gracefully"
      end)
    end
    
    test "concurrent MCP stream creation handles resource limits" do
      user_id = "test_user"
      session_id = "test_session_#{:erlang.unique_integer()}"
      
      # Try to create more streams than the limit
      stream_tasks = Enum.map(1..15, fn i ->
        Task.async(fn ->
          StreamBridge.create_stream(
            "conn_#{i}",
            user_id,
            session_id,
            %{"client_id" => "#{user_id}_client_#{i}"}
          )
        end)
      end)
      
      results = Task.await_many(stream_tasks, 5000)
      
      # Some should succeed, some should fail due to limits
      successes = Enum.count(results, &match?({:ok, _}, &1))
      failures = Enum.count(results, &match?({:error, _}, &1))
      
      assert successes <= 10, "Should not exceed max concurrent streams"
      assert failures > 0, "Some requests should fail due to limits"
    end
  end
  
  describe "LSP method security validation" do
    test "sanitizes and validates LSP method parameters" do
      malicious_params = [
        # Path traversal attempts
        %{"path" => "../../../etc/passwd"},
        %{"root" => "../../../../root/.ssh/"},
        
        # Code injection attempts  
        %{"query" => "; rm -rf /"},
        %{"pattern" => "$(rm -rf /)"},
        
        # Resource exhaustion
        %{"max_results" => 999_999_999},
        %{"max_depth" => 999_999},
        
        # Malformed data
        %{"textDocument" => %{"uri" => nil}},
        %{"position" => %{"line" => -1, "character" => -1}}
      ]
      
      Enum.each(malicious_params, fn params ->
        message = %{
          "jsonrpc" => "2.0", 
          "id" => 1,
          "method" => "lang.fs.search",
          "params" => params
        }
        
        result = Dispatch.process(message)
        
        # Should either return error or sanitized result, never execute malicious input
        assert result == nil or 
               match?(%{"error" => _}, result) or
               (match?(%{"result" => _}, result) and safe_result?(result)),
               "Malicious input should be rejected or sanitized"
      end)
    end
    
    test "validates MCP request security through StreamBridge" do
      # Test MCP request validation
      malicious_requests = [
        # File system access attempts
        %{"method" => "fs/read", "params" => %{"path" => "/etc/passwd"}},
        %{"method" => "fs/write", "params" => %{"path" => "/tmp/malicious"}},
        
        # Process execution attempts  
        %{"method" => "exec", "params" => %{"command" => "rm -rf /"}},
        
        # Network access attempts
        %{"method" => "http", "params" => %{"url" => "https://malicious.com/exfiltrate"}}
      ]
      
      {:ok, stream_id} = StreamBridge.create_stream(
        "test_conn",
        "test_user", 
        "test_session",
        %{"client_id" => "test_user_security_client"}
      )
      
      Enum.each(malicious_requests, fn request ->
        result = StreamBridge.stream_mcp_request(stream_id, request)
        
        # Should reject dangerous requests
        assert match?({:error, {:invalid_request, _}}, result),
               "Malicious MCP request should be rejected"
      end)
    end
  end
  
  describe "Resource exhaustion protection" do
    test "limits concurrent LSP operations per client" do
      host = (System.get_env("LSP_HOST") || "127.0.0.1") |> to_charlist()
      port = String.to_integer(System.get_env("LSP_PORT") || "4001")
      client_id = "resource_test_client"
      
      {:ok, conn} = Client.connect(
        host: host,
        port: port, 
        client_id: client_id,
        root_path: System.cwd!(),
        timeout: 5_000
      )
      
      # Flood the server with expensive operations
      operations = Enum.map(1..50, fn i ->
        Task.async(fn ->
          Client.request_with_connection(conn, "lang.fs.search", %{
            "path" => System.cwd!(),
            "query" => "pattern_#{i}",
            "max_results" => 1000
          }, timeout: 2_000)
        end)
      end)
      
      results = Task.await_many(operations, 5_000)
      
      # Should handle resource limits gracefully
      timeouts = Enum.count(results, &match?({:error, :timeout}, &1))
      errors = Enum.count(results, &match?({:error, _}, &1))
      
      assert timeouts + errors > 0, "Should have some timeouts/errors under load"
      
      Client.disconnect(conn)
    end
  end
  
  # Helper functions
  defp notify_conn(%{socket: socket}, method, params) do
    payload = %{"jsonrpc" => "2.0", "method" => method, "params" => params}
    {:ok, json} = Jason.encode_to_iodata(payload)
    len = :erlang.iolist_size(json)
    header = ["Content-Length: ", Integer.to_string(len), "\r\n\r\n"]
    :gen_tcp.send(socket, [header, json])
  end
  
  defp safe_result?(%{"result" => result}) when is_map(result) do
    # Check that result doesn't contain sensitive paths or data
    json_str = Jason.encode!(result) 
    not String.contains?(json_str, ["/etc/", "/root/", "passwd", "shadow"])
  end
  defp safe_result?(_), do: true
end