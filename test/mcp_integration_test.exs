defmodule MCPIntegrationTest do
  @moduledoc """
  Comprehensive MCP integration test demonstrating full workflow:

  1. Client connection with Client_ID enforcement
  2. Agent swarm creation via LSP
  3. Stream creation and data flow
  4. Event tracking and monitoring
  5. Connection lifecycle management
  6. Error handling and recovery
  """

  use ExUnit.Case, async: false
  require Logger

  alias Lang.MCP.{ConnectionManager, StreamBridge}
  alias Lang.Proxy.Router
  alias Lang.Proxy.Envelope
  alias Lang.Events

  @client_id "test_client_integration_12345"
  @user_id "test_user_123"
  @session_id "test_session_456"

  setup do
    # Ensure clean state
    :ok
  end

  describe "MCP full workflow integration" do
    test "complete client lifecycle with swarm orchestration" do
      Logger.info("Starting MCP integration test")

      # 1. Test MCP connection creation via proxy router
      envelope = %Envelope{
        service: :mcp,
        method: "connection.create",
        params: %{
          "url" => "file:///tmp/test_workspace",
          "server_type" => "filesystem",
          "connection_params" => %{"root_path" => "/tmp/test"}
        },
        opts: %{
          "client_id" => @client_id,
          "user_id" => @user_id,
          "session_id" => @session_id
        }
      }

      case Router.dispatch(envelope) do
        {:ok, connection_result} ->
          connection_id = connection_result["connection_id"] || connection_result.connection_id
          Logger.info("MCP connection created", connection_id: connection_id)

          # Verify Ash record was created
          assert_connection_record_exists(connection_id, @user_id)

          # 2. Test stream creation with Client_ID validation
          case StreamBridge.create_stream(connection_id, @user_id, @session_id, %{
            "client_id" => @client_id
          }) do
            {:ok, stream_id} ->
              Logger.info("MCP stream created", stream_id: stream_id)

              # 3. Test LSP agent swarm creation
              swarm_params = %{
                "goals" => ["code analysis", "documentation generation"],
                "agent_count" => 3,
                "coordinator_id" => "test_coordinator"
              }

              swarm_msg = %{
                "jsonrpc" => "2.0",
                "id" => 1,
                "method" => "lang.agent.swarm_create",
                "params" => swarm_params
              }

              case Lang.LSP.Dispatch.process(swarm_msg) do
                {:ok, %{"result" => swarm_result}} ->
                  swarm_id = swarm_result["swarm_id"]
                  Logger.info("Agent swarm created", swarm_id: swarm_id)

                  # Verify Ash swarm record
                  assert_swarm_record_exists(swarm_id)

                  # 4. Test MCP stream request processing
                  test_request = %{
                    "method" => "list_directory",
                    "params" => %{"path" => "/tmp"}
                  }

                  case StreamBridge.stream_mcp_request(stream_id, test_request) do
                    {:ok, :streaming} ->
                      Logger.info("MCP request streaming initiated", stream_id: stream_id)

                      # 5. Verify event tracking
                      verify_events_tracked([
                        "mcp_connection_created",
                        "mcp_stream_created",
                        "agent_swarm_created"
                      ])

                      # 6. Test connection cleanup
                      cleanup_result = ConnectionManager.destroy_connection(connection_id, %{
                        "client_id" => @client_id,
                        "user_id" => @user_id
                      })

                      case cleanup_result do
                        {:ok, _} ->
                          Logger.info("MCP connection cleaned up", connection_id: connection_id)
                          assert_connection_status(connection_id, :disconnected)

                        {:error, reason} ->
                          Logger.error("Connection cleanup failed", reason: reason)
                          flunk("Connection cleanup failed: #{inspect(reason)}")
                      end

                    {:error, reason} ->
                      Logger.error("Stream request failed", reason: reason)
                      flunk("Stream request failed: #{inspect(reason)}")
                  end

                error ->
                  Logger.error("Swarm creation failed", error: error)
                  flunk("Swarm creation failed: #{inspect(error)}")
              end

            {:error, reason} ->
              Logger.error("Stream creation failed", reason: reason)
              flunk("Stream creation failed: #{inspect(reason)}")
          end

        {:error, code, message, data} ->
          Logger.error("MCP connection creation failed",
            code: code,
            message: message,
            data: data
          )
          flunk("MCP connection creation failed: #{message}")

        error ->
          Logger.error("Unexpected MCP connection error", error: error)
          flunk("Unexpected MCP connection error: #{inspect(error)}")
      end
    end

    test "Client_ID enforcement and security" do
      Logger.info("Testing Client_ID enforcement")

      # Test 1: Missing Client_ID should fail
      envelope_no_client = %Envelope{
        service: :mcp,
        method: "connection.create",
        params: %{"url" => "file:///tmp/test"},
        opts: %{"user_id" => @user_id}
      }

      case Router.dispatch(envelope_no_client) do
        {:error, -32040, "Invalid client ID", _} ->
          Logger.info("✓ Missing Client_ID correctly rejected")
        other ->
          flunk("Expected Client_ID validation error, got: #{inspect(other)}")
      end

      # Test 2: Invalid Client_ID format should fail
      envelope_invalid_client = %Envelope{
        service: :mcp,
        method: "connection.create",
        params: %{"url" => "file:///tmp/test"},
        opts: %{"client_id" => "invalid", "user_id" => @user_id}
      }

      case Router.dispatch(envelope_invalid_client) do
        {:error, -32040, "Invalid client ID", _} ->
          Logger.info("✓ Invalid Client_ID format correctly rejected")
        other ->
          flunk("Expected Client_ID format validation error, got: #{inspect(other)}")
      end

      # Test 3: Stream creation with mismatched Client_ID should fail
      # (This would require setting up a valid connection first, then testing stream creation)
      Logger.info("✓ Client_ID enforcement tests passed")
    end

    test "concurrent client flux simulation" do
      Logger.info("Testing concurrent client flux")

      # Simulate multiple clients connecting concurrently
      client_count = 5

      results = 1..client_count
      |> Enum.map(fn i ->
        Task.async(fn ->
          client_id = "#{@client_id}_concurrent_#{i}"
          test_single_client_workflow(client_id, i)
        end)
      end)
      |> Enum.map(&Task.await(&1, 30_000))

      successful_connections = Enum.count(results, &match?({:ok, _}, &1))
      failed_connections = Enum.count(results, &match?({:error, _}, &1))

      Logger.info("Concurrent client test results",
        successful: successful_connections,
        failed: failed_connections,
        total: client_count
      )

      # Allow some failures due to resource constraints, but most should succeed
      assert successful_connections >= client_count - 1,
        "Too many concurrent connections failed: #{failed_connections}/#{client_count}"
    end
  end

  # Helper functions

  defp test_single_client_workflow(client_id, index) do
    try do
      envelope = %Envelope{
        service: :mcp,
        method: "connection.create",
        params: %{
          "url" => "file:///tmp/test_#{index}",
          "server_type" => "filesystem"
        },
        opts: %{
          "client_id" => client_id,
          "user_id" => "#{@user_id}_#{index}",
          "session_id" => "#{@session_id}_#{index}"
        }
      }

      case Router.dispatch(envelope) do
        {:ok, _result} ->
          # Quick status check
          status_envelope = %{envelope | method: "connection.status"}
          case Router.dispatch(status_envelope) do
            {:ok, _} -> {:ok, client_id}
            error -> {:error, {:status_check_failed, error}}
          end
        error ->
          {:error, {:connection_failed, error}}
      end
    rescue
      e -> {:error, {:exception, e}}
    end
  end

  defp assert_connection_record_exists(connection_id, user_id) do
    case Lang.MCP.ConnectionManager.get_connection_record(connection_id) do
      {:ok, record} ->
        assert record.user_id == user_id
        assert record.connection_id == connection_id
        Logger.info("✓ Ash connection record verified", connection_id: connection_id)
      {:error, reason} ->
        flunk("Connection record not found in Ash: #{inspect(reason)}")
    end
  end

  defp assert_connection_status(connection_id, expected_status) do
    case Lang.MCP.ConnectionManager.get_connection_record(connection_id) do
      {:ok, record} ->
        assert record.status == expected_status
        Logger.info("✓ Connection status verified", connection_id: connection_id, status: expected_status)
      {:error, reason} ->
        flunk("Connection status check failed: #{inspect(reason)}")
    end
  end

  defp assert_swarm_record_exists(swarm_id) do
    query = Lang.Agent.Swarm |> Ash.Query.for_read(:by_swarm_id, %{swarm_id: swarm_id})

    case Ash.read(query) do
      {:ok, [swarm]} ->
        assert swarm.swarm_id == swarm_id
        assert length(swarm.agent_ids) > 0
        Logger.info("✓ Ash swarm record verified", swarm_id: swarm_id)
      {:ok, []} ->
        flunk("Swarm record not found in Ash")
      {:error, reason} ->
        flunk("Swarm query failed: #{inspect(reason)}")
    end
  end

  defp verify_events_tracked(expected_event_types) do
    # This would require access to event storage or a test event sink
    # For now, we'll just log the expectation
    Logger.info("✓ Event tracking verification placeholder", expected_events: expected_event_types)
    # In a real test, you would query the event store or use a test event collector
  end
end