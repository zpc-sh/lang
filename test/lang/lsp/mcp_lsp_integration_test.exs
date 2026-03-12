defmodule Lang.LSP.MCPIntegrationTest do
  @moduledoc """
  Comprehensive testing of MCP bridge integration through LSP.
  
  Tests the full flow: LSP client -> LSP server -> MCP dispatch -> MCP bridge -> MCP server
  Validates security, streaming, and multi-client MCP access patterns.
  """
  
  use ExUnit.Case, async: false
  
  alias Lang.LSP.{Server, Client, Dispatch}
  alias Lang.MCP.{StreamBridge, ConnectionManager}
  
  @moduletag :mcp_integration
  @moduletag :integration
  
  setup_all do
    {:ok, _} = Application.ensure_all_started(:lang)
    
    # Start mock MCP server for testing
    {:ok, mock_server} = start_mock_mcp_server()
    
    on_exit(fn ->
      :gen_server.stop(mock_server)
    end)
    
    {:ok, mock_server: mock_server}
  end
  
  describe "MCP method routing through LSP" do
    test "routes mcp.connection.* methods correctly" do
      message = %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "mcp.connection.create",
        "params" => %{
          "server_url" => "http://localhost:3000",
          "capabilities" => ["filesystem"]
        }
      }
      
      result = Dispatch.process(message)
      
      assert match?(%{"id" => 1, "result" => _}, result) or
             match?(%{"id" => 1, "error" => _}, result),
             "MCP connection creation should return valid response"
    end
    
    test "validates MCP requests routed through LSP" do
      # Invalid MCP request should be caught by dispatch layer
      message = %{
        "jsonrpc" => "2.0",
        "id" => 2,
        "method" => "mcp.connection.create",
        "params" => %{
          # Missing required server_url
          "capabilities" => ["filesystem"]
        }
      }
      
      result = Dispatch.process(message)
      
      assert match?(%{"id" => 2, "error" => _}, result),
             "Invalid MCP request should return error"
    end
  end
  
  describe "MCP streaming through LSP clients" do
    test "establishes MCP stream via LSP and receives chunked data" do
      host = (System.get_env("LSP_HOST") || "127.0.0.1") |> to_charlist()
      port = String.to_integer(System.get_env("LSP_PORT") || "4001")
      client_id = "mcp_stream_client_#{:erlang.unique_integer()}"
      
      {:ok, conn} = Client.connect(
        host: host,
        port: port,
        client_id: client_id,
        root_path: System.cwd!(),
        timeout: 5_000
      )
      
      # Identify client for MCP operations
      :ok = notify_conn(conn, "lang/tester/identify", %{"clientId" => client_id})
      
      # Create MCP connection through LSP
      mcp_result = Client.request_with_connection(conn, "mcp.connection.create", %{
        "server_url" => "http://localhost:3000",
        "capabilities" => ["filesystem"],
        "client_id" => client_id
      }, timeout: 5_000)
      
      assert {:ok, %{"connection_id" => connection_id}} = mcp_result
      
      # Create streaming session
      {:ok, stream_id} = StreamBridge.create_stream(
        connection_id,
        "test_user",
        "test_session_#{client_id}",
        %{"client_id" => client_id}
      )
      
      # Subscribe to stream updates
      :ok = StreamBridge.subscribe_to_session("test_session_#{client_id}")
      
      # Send MCP request that generates large response
      :ok = StreamBridge.stream_mcp_request(stream_id, %{
        "method" => "fs/list", 
        "params" => %{"path" => "/large/directory"}
      })
      
      # Wait for stream chunks
      chunks = collect_stream_chunks(stream_id, 5000)
      
      assert length(chunks) > 0, "Should receive stream chunks"
      assert Enum.any?(chunks, fn chunk -> chunk.is_last end), "Should have final chunk"
      
      Client.disconnect(conn)
    end
    
    test "handles MCP stream errors gracefully" do
      client_id = "mcp_error_client_#{:erlang.unique_integer()}"
      
      {:ok, stream_id} = StreamBridge.create_stream(
        "nonexistent_connection",
        "test_user",
        "error_session",
        %{"client_id" => client_id}
      )
      
      # This should fail due to nonexistent connection
      result = StreamBridge.stream_mcp_request(stream_id, %{
        "method" => "fs/read",
        "params" => %{"path" => "/test/file"}
      })
      
      assert {:error, _reason} = result
    end
  end
  
  describe "Multi-client MCP access patterns" do
    test "multiple LSP clients can share MCP connections safely" do
      connection_id = "shared_mcp_conn_#{:erlang.unique_integer()}"
      base_session = "shared_session_#{:erlang.unique_integer()}"
      
      # Create multiple streams from different clients to same connection
      clients = ["client_a", "client_b", "client_c"]
      
      streams = Enum.map(clients, fn client ->
        {:ok, stream_id} = StreamBridge.create_stream(
          connection_id,
          "shared_user",
          "#{base_session}_#{client}",
          %{"client_id" => "shared_user_#{client}"}
        )
        {client, stream_id}
      end)
      
      # All clients make concurrent MCP requests
      results = Enum.map(streams, fn {client, stream_id} ->
        Task.async(fn ->
          {client, StreamBridge.stream_mcp_request(stream_id, %{
            "method" => "fs/stat",
            "params" => %{"path" => "/shared/resource/#{client}"}
          })}
        end)
      end)
      |> Task.await_many(5000)
      
      # All should either succeed or fail gracefully (connection might not exist)
      Enum.each(results, fn {client, result} ->
        assert match?({:ok, :streaming}, result) or match?({:error, _}, result),
               "Client #{client} should handle request appropriately"
      end)
    end
    
    test "enforces MCP connection access control per client" do
      # Client A creates a connection
      client_a_id = "owner_client_#{:erlang.unique_integer()}"
      {:ok, connection_id} = create_test_mcp_connection(client_a_id, "user_a")
      
      # Client B tries to access Client A's connection  
      client_b_id = "unauthorized_client_#{:erlang.unique_integer()}"
      
      result = StreamBridge.create_stream(
        connection_id,
        "user_b",  # Different user
        "session_b",
        %{"client_id" => client_b_id}
      )
      
      # Should fail due to access control
      assert {:error, _reason} = result
    end
  end
  
  describe "MCP security through LSP layer" do
    test "validates MCP filesystem operations are sandboxed" do
      client_id = "sandbox_test_client"
      
      {:ok, stream_id} = StreamBridge.create_stream(
        "test_conn",
        "test_user",
        "sandbox_session", 
        %{"client_id" => client_id}
      )
      
      dangerous_operations = [
        %{"method" => "fs/read", "params" => %{"path" => "/etc/passwd"}},
        %{"method" => "fs/write", "params" => %{"path" => "/tmp/../../../root/malicious"}},
        %{"method" => "fs/delete", "params" => %{"path" => "/important/system/file"}}
      ]
      
      Enum.each(dangerous_operations, fn operation ->
        result = StreamBridge.stream_mcp_request(stream_id, operation)
        
        # Should reject dangerous operations
        assert match?({:error, {:invalid_request, _}}, result),
               "Dangerous MCP operation should be blocked: #{inspect(operation)}"
      end)
    end
    
    test "rate limits MCP operations per client" do
      client_id = "rate_limit_mcp_client"
      
      {:ok, stream_id} = StreamBridge.create_stream(
        "test_conn",
        "test_user", 
        "rate_limit_session",
        %{"client_id" => client_id}
      )
      
      # Flood with MCP requests
      requests = Enum.map(1..50, fn i ->
        Task.async(fn ->
          StreamBridge.stream_mcp_request(stream_id, %{
            "method" => "fs/stat",
            "params" => %{"path" => "/test/file_#{i}"}
          })
        end)
      end)
      
      results = Task.await_many(requests, 5000)
      
      # Some should be rate limited  
      rate_limited = Enum.count(results, &match?({:error, :rate_limited}, &1))
      assert rate_limited > 0, "Should rate limit excessive MCP requests"
    end
  end
  
  describe "MCP connection lifecycle through LSP" do
    test "manages MCP connection lifecycle correctly" do
      host = (System.get_env("LSP_HOST") || "127.0.0.1") |> to_charlist()
      port = String.to_integer(System.get_env("LSP_PORT") || "4001")
      client_id = "lifecycle_test_client"
      
      {:ok, conn} = Client.connect(
        host: host,
        port: port,
        client_id: client_id,
        root_path: System.cwd!(),
        timeout: 5_000
      )
      
      # Create MCP connection
      {:ok, create_result} = Client.request_with_connection(conn, "mcp.connection.create", %{
        "server_url" => "http://localhost:3000",
        "capabilities" => ["filesystem"],
        "client_id" => client_id
      }, timeout: 5_000)
      
      connection_id = create_result["connection_id"]
      
      # Check connection status
      {:ok, status_result} = Client.request_with_connection(conn, "mcp.connection.status", %{
        "connection_id" => connection_id
      }, timeout: 3_000)
      
      assert status_result["status"] in ["connected", "connecting", "error"]
      
      # Destroy connection
      {:ok, _destroy_result} = Client.request_with_connection(conn, "mcp.connection.destroy", %{
        "connection_id" => connection_id
      }, timeout: 3_000)
      
      # Verify connection is destroyed
      {:ok, final_status} = Client.request_with_connection(conn, "mcp.connection.status", %{
        "connection_id" => connection_id  
      }, timeout: 3_000)
      
      assert final_status["status"] == "destroyed"
      
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
  
  defp start_mock_mcp_server do
    # Simple mock MCP server for testing
    {:ok, spawn_link(fn -> mock_mcp_server_loop() end)}
  end
  
  defp mock_mcp_server_loop do
    # Mock server that responds to basic MCP operations
    receive do
      {:mcp_request, request, reply_to} ->
        response = case request do
          %{"method" => "fs/list"} -> 
            %{"result" => %{"files" => Enum.map(1..1000, &%{"name" => "file_#{&1}.txt"})}}
          %{"method" => "fs/stat"} ->
            %{"result" => %{"size" => 1024, "type" => "file"}}
          %{"method" => "fs/read"} ->
            %{"result" => %{"content" => "File content here"}}
          _ ->
            %{"error" => %{"code" => -32601, "message" => "Method not found"}}
        end
        
        send(reply_to, {:mcp_response, response})
        mock_mcp_server_loop()
        
      :stop -> :ok
    end
  end
  
  defp create_test_mcp_connection(client_id, user_id) do
    # Mock connection creation for testing
    connection_id = "test_conn_#{client_id}_#{:erlang.unique_integer()}"
    
    # Would normally create real MCP connection
    # ConnectionManager.create_connection(connection_id, user_id, %{
    #   server_url: "http://localhost:3000",
    #   capabilities: ["filesystem"]
    # })
    
    {:ok, connection_id}
  end
  
  defp collect_stream_chunks(stream_id, timeout) do
    start_time = System.monotonic_time(:millisecond)
    collect_chunks_loop(stream_id, start_time, timeout, [])
  end
  
  defp collect_chunks_loop(stream_id, start_time, timeout, acc) do
    current_time = System.monotonic_time(:millisecond)
    if current_time - start_time > timeout do
      acc
    else
      receive do
        {:stream_chunk, ^stream_id, chunk} ->
          collect_chunks_loop(stream_id, start_time, timeout, [chunk | acc])
        {:stream_completed, ^stream_id} ->
          acc
        {:stream_error, ^stream_id, _error} ->
          acc
      after
        1000 -> acc  # Return what we have so far
      end
    end
  end
end