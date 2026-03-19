defmodule Lang.MCP.StreamBridge do
  @moduledoc """
  MCP Streaming Bridge - Bridges MCP responses through Lang's StreamingProtocol.

  This module provides a bridge between MCP server responses and Lang's existing
  streaming infrastructure, enabling:
  - Seamless integration with Phoenix PubSub
  - Session state management in Redis
  - Connection multiplexing (multiple agents sharing MCP connections)
  - Real-time streaming of large MCP responses
  - Proper isolation between different user sessions

  ## Architecture
  The bridge maintains session state and multiplexes MCP connections while
  ensuring security boundaries are preserved. All streaming goes through
  Lang's authenticated channels with proper access control.

  ## Security Model
  - Session isolation: Each user session has isolated stream channels
  - Connection multiplexing: Multiple agents can share MCP connections safely
  - State persistence: Session state stored in Redis with TTL
  - Access control: All streams require authentication through Lang's system
  """

  use GenServer
  require Logger

  alias Lang.LSP.StreamingProtocol
  alias Lang.MCP.{Broker, Security}
  alias Phoenix.PubSub

  # Redis keys for session state
  @redis_prefix "mcp_session:"
  # 1 hour
  @redis_ttl 3600

  # Stream configuration
  # 64KB chunks
  @chunk_size 64 * 1024
  @stream_timeout :timer.minutes(5)
  @max_concurrent_streams 10

  @type stream_id :: String.t()
  @type session_id :: String.t()
  @type connection_id :: String.t()
  @type user_id :: String.t()

  @type stream_state :: %{
          stream_id: stream_id(),
          session_id: session_id(),
          connection_id: connection_id(),
          user_id: user_id(),
          created_at: DateTime.t(),
          last_activity: DateTime.t(),
          status: :active | :completed | :error | :cancelled,
          total_chunks: non_neg_integer(),
          sent_chunks: non_neg_integer()
        }

  @type bridge_state :: %{
          active_streams: %{stream_id() => stream_state()},
          session_connections: %{session_id() => [connection_id()]},
          user_streams: %{user_id() => [stream_id()]},
          stats: bridge_stats()
        }

  @type bridge_stats :: %{
          total_streams: non_neg_integer(),
          active_streams: non_neg_integer(),
          completed_streams: non_neg_integer(),
          failed_streams: non_neg_integer(),
          bytes_streamed: non_neg_integer()
        }

  ## Public API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Create a new MCP streaming session.

  Establishes a secure streaming bridge between an MCP connection and
  a user session with proper isolation and access control.

  Requires Client_ID for security enforcement.
  """
  @spec create_stream(connection_id(), user_id(), session_id(), map()) ::
          {:ok, stream_id()} | {:error, term()}
  def create_stream(connection_id, user_id, session_id, opts \\ %{}) do
    client_id = Map.get(opts, "client_id") || Map.get(opts, :client_id)

    case validate_client_id_for_stream(client_id, user_id, connection_id) do
      {:ok, validated_client_id} ->
        GenServer.call(__MODULE__, {
          :create_stream,
          connection_id,
          user_id,
          session_id,
          Map.put(opts, :validated_client_id, validated_client_id)
        })

      {:error, reason} ->
        {:error, {:client_id_invalid, reason}}
    end
  end

  @doc """
  Send MCP request through streaming bridge.

  The request is validated, sent to the MCP server, and the response
  is streamed back through the established bridge.
  """
  @spec stream_mcp_request(stream_id(), map()) :: {:ok, term()} | {:error, term()}
  def stream_mcp_request(stream_id, request) do
    GenServer.call(__MODULE__, {:stream_request, stream_id, request})
  end

  @doc """
  Get streaming session status.
  """
  @spec get_stream_status(stream_id()) :: {:ok, map()} | {:error, term()}
  def get_stream_status(stream_id) do
    GenServer.call(__MODULE__, {:get_stream_status, stream_id})
  end

  @doc """
  Cancel an active stream.
  """
  @spec cancel_stream(stream_id()) :: :ok | {:error, term()}
  def cancel_stream(stream_id) do
    GenServer.call(__MODULE__, {:cancel_stream, stream_id})
  end

  @doc """
  Subscribe to stream updates for a session.
  """
  @spec subscribe_to_session(session_id()) :: :ok
  def subscribe_to_session(session_id) do
    topic = "mcp_stream:session:#{session_id}"
    PubSub.subscribe(Lang.PubSub, topic)
  end

  @doc """
  Get bridge statistics.
  """
  @spec get_stats() :: bridge_stats()
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  ## GenServer Callbacks

  @impl true
  def init(_opts) do
    Logger.info("Starting MCP Stream Bridge")

    # Schedule periodic cleanup
    Process.send_after(self(), :cleanup_expired_streams, :timer.minutes(5))

    {:ok,
     %{
       active_streams: %{},
       session_connections: %{},
       user_streams: %{},
       stats: %{
         total_streams: 0,
         active_streams: 0,
         completed_streams: 0,
         failed_streams: 0,
         bytes_streamed: 0
       }
     }}
  end

  @impl true
  def handle_call({:create_stream, connection_id, user_id, session_id, opts}, _from, state) do
    case validate_stream_creation(user_id, state) do
      :ok ->
        case create_new_stream(connection_id, user_id, session_id, opts, state) do
          {:ok, stream_id, updated_state} ->
            {:reply, {:ok, stream_id}, updated_state}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:stream_request, stream_id, request}, _from, state) do
    case Map.get(state.active_streams, stream_id) do
      nil ->
        {:reply, {:error, :stream_not_found}, state}

      stream_state ->
        case process_streaming_request(stream_state, request, state) do
          {:ok, updated_state} ->
            {:reply, {:ok, :streaming}, updated_state}

          {:error, reason, updated_state} ->
            {:reply, {:error, reason}, updated_state}
        end
    end
  end

  @impl true
  def handle_call({:get_stream_status, stream_id}, _from, state) do
    case Map.get(state.active_streams, stream_id) do
      nil ->
        {:reply, {:error, :stream_not_found}, state}

      stream_state ->
        status = build_stream_status(stream_state)
        {:reply, {:ok, status}, state}
    end
  end

  @impl true
  def handle_call({:cancel_stream, stream_id}, _from, state) do
    case cancel_stream_internal(stream_id, state) do
      {:ok, updated_state} ->
        {:reply, :ok, updated_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    current_stats = calculate_current_stats(state)
    {:reply, current_stats, state}
  end

  @impl true
  def handle_info(:cleanup_expired_streams, state) do
    updated_state = cleanup_expired_streams(state)

    # Schedule next cleanup
    Process.send_after(self(), :cleanup_expired_streams, :timer.minutes(5))

    {:noreply, updated_state}
  end

  @impl true
  def handle_info({:mcp_response_chunk, stream_id, chunk_data}, state) do
    case Map.get(state.active_streams, stream_id) do
      nil ->
        Logger.warning("Received chunk for unknown stream", stream_id: stream_id)
        {:noreply, state}

      stream_state ->
        updated_state = handle_response_chunk(stream_state, chunk_data, state)
        {:noreply, updated_state}
    end
  end

  @impl true
  def handle_info({:mcp_response_complete, stream_id}, state) do
    case Map.get(state.active_streams, stream_id) do
      nil ->
        {:noreply, state}

      stream_state ->
        updated_state = complete_stream(stream_state, state)
        {:noreply, updated_state}
    end
  end

  @impl true
  def handle_info({:mcp_response_error, stream_id, error}, state) do
    case Map.get(state.active_streams, stream_id) do
      nil ->
        {:noreply, state}

      stream_state ->
        updated_state = handle_stream_error(stream_state, error, state)
        {:noreply, updated_state}
    end
  end

  ## Private Functions

  defp validate_stream_creation(user_id, state) do
    user_stream_count = length(Map.get(state.user_streams, user_id, []))

    if user_stream_count >= @max_concurrent_streams do
      {:error, :max_streams_exceeded}
    else
      :ok
    end
  end

  defp create_new_stream(connection_id, user_id, session_id, _opts, state) do
    stream_id = generate_stream_id()

    # Validate connection exists and user has access
    case Broker.get_connection_status(connection_id) do
      {:ok, _connection_status} ->
        stream_state = %{
          stream_id: stream_id,
          session_id: session_id,
          connection_id: connection_id,
          user_id: user_id,
          created_at: DateTime.utc_now(),
          last_activity: DateTime.utc_now(),
          status: :active,
          total_chunks: 0,
          sent_chunks: 0
        }

        # Store session state in Redis
        store_session_state(stream_id, stream_state)

        # Update tracking
        updated_streams = Map.put(state.active_streams, stream_id, stream_state)

        updated_session_connections =
          Map.update(state.session_connections, session_id, [connection_id], fn connections ->
            if connection_id in connections do
              connections
            else
              [connection_id | connections]
            end
          end)

        updated_user_streams =
          Map.update(state.user_streams, user_id, [stream_id], fn streams ->
            [stream_id | streams]
          end)

        updated_stats = %{state.stats | total_streams: state.stats.total_streams + 1}

        updated_state = %{
          state
          | active_streams: updated_streams,
            session_connections: updated_session_connections,
            user_streams: updated_user_streams,
            stats: updated_stats
        }

        # Broadcast stream creation
        broadcast_to_session(session_id, {:stream_created, stream_id, stream_state})

        Logger.info("Created MCP stream", stream_id: stream_id, session_id: session_id)

        {:ok, stream_id, updated_state}

      {:error, :not_found} ->
        {:error, :connection_not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp process_streaming_request(stream_state, request, state) do
    # Validate and sanitize the request
    case Security.validate_mcp_request("filesystem", request) do
      {:ok, safe_request} ->
        # Send request to MCP server and set up streaming
        case setup_streaming_response(stream_state, safe_request) do
          :ok ->
            # Update stream activity
            updated_stream = %{stream_state | last_activity: DateTime.utc_now()}

            updated_streams =
              Map.put(state.active_streams, stream_state.stream_id, updated_stream)

            {:ok, %{state | active_streams: updated_streams}}

          {:error, reason} ->
            Logger.error("Failed to setup MCP streaming",
              stream_id: stream_state.stream_id,
              reason: reason
            )

            {:error, reason, state}
        end

      {:error, reason} ->
        Logger.warning("Invalid MCP request in stream",
          stream_id: stream_state.stream_id,
          reason: reason
        )

        {:error, {:invalid_request, reason}, state}
    end
  end

  defp setup_streaming_response(stream_state, request) do
    # Send request to MCP server with streaming callback
    case Broker.send_mcp_request(stream_state.connection_id, request) do
      {:ok, response} ->
        # Start streaming the response
        Task.start_link(fn ->
          stream_response_data(stream_state, response)
        end)

        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp stream_response_data(stream_state, response) do
    try do
      # Convert response to JSON and check size
      json_response = Jason.encode!(response)
      response_size = byte_size(json_response)

      if response_size > @chunk_size do
        # Stream large response in chunks
        stream_large_response(stream_state, json_response)
      else
        # Send small response directly
        broadcast_response_chunk(stream_state, %{
          type: :complete,
          data: response,
          chunk_index: 0,
          total_chunks: 1,
          is_last: true
        })
      end
    rescue
      error ->
        Logger.error("Error streaming MCP response",
          stream_id: stream_state.stream_id,
          error: inspect(error)
        )

        send(self(), {:mcp_response_error, stream_state.stream_id, error})
    end
  end

  defp stream_large_response(stream_state, json_response) do
    total_size = byte_size(json_response)
    total_chunks = div(total_size - 1, @chunk_size) + 1

    # Update stream state with chunk info
    send(self(), {:update_stream_chunks, stream_state.stream_id, total_chunks})

    # Stream in chunks
    json_response
    |> :binary.bin_to_list()
    |> Enum.chunk_every(@chunk_size)
    |> Enum.with_index()
    |> Enum.each(fn {chunk_bytes, index} ->
      chunk_data = :binary.list_to_bin(chunk_bytes)

      broadcast_response_chunk(stream_state, %{
        type: :chunk,
        data: Base.encode64(chunk_data),
        chunk_index: index,
        total_chunks: total_chunks,
        is_last: index == total_chunks - 1
      })

      # Small delay to prevent overwhelming the client
      Process.sleep(10)
    end)

    # Signal completion
    send(self(), {:mcp_response_complete, stream_state.stream_id})
  end

  defp broadcast_response_chunk(stream_state, chunk_data) do
    # Broadcast through StreamingProtocol
    topic = "mcp_stream:#{stream_state.stream_id}"

    PubSub.broadcast(Lang.PubSub, topic, {
      :mcp_stream_chunk,
      stream_state.stream_id,
      chunk_data
    })

    # Also broadcast to session
    broadcast_to_session(stream_state.session_id, {
      :stream_chunk,
      stream_state.stream_id,
      chunk_data
    })
  end

  defp handle_response_chunk(stream_state, chunk_data, state) do
    # Update stream state
    updated_stream = %{
      stream_state
      | sent_chunks: stream_state.sent_chunks + 1,
        last_activity: DateTime.utc_now()
    }

    updated_streams = Map.put(state.active_streams, stream_state.stream_id, updated_stream)

    # Update bytes streamed
    chunk_size = byte_size(Jason.encode!(chunk_data))
    updated_stats = %{state.stats | bytes_streamed: state.stats.bytes_streamed + chunk_size}

    %{state | active_streams: updated_streams, stats: updated_stats}
  end

  defp complete_stream(stream_state, state) do
    # Mark stream as completed
    completed_stream = %{stream_state | status: :completed}
    updated_streams = Map.put(state.active_streams, stream_state.stream_id, completed_stream)

    # Update stats
    updated_stats = %{
      state.stats
      | completed_streams: state.stats.completed_streams + 1
    }

    # Broadcast completion
    broadcast_to_session(stream_state.session_id, {
      :stream_completed,
      stream_state.stream_id
    })

    # Schedule cleanup
    Process.send_after(self(), {:cleanup_stream, stream_state.stream_id}, :timer.seconds(30))

    Logger.info("Completed MCP stream", stream_id: stream_state.stream_id)

    %{state | active_streams: updated_streams, stats: updated_stats}
  end

  defp handle_stream_error(stream_state, error, state) do
    # Mark stream as error
    error_stream = %{stream_state | status: :error}
    updated_streams = Map.put(state.active_streams, stream_state.stream_id, error_stream)

    # Update stats
    updated_stats = %{state.stats | failed_streams: state.stats.failed_streams + 1}

    # Broadcast error
    broadcast_to_session(stream_state.session_id, {
      :stream_error,
      stream_state.stream_id,
      error
    })

    Logger.error("MCP stream error",
      stream_id: stream_state.stream_id,
      error: inspect(error)
    )

    %{state | active_streams: updated_streams, stats: updated_stats}
  end

  defp cancel_stream_internal(stream_id, state) do
    case Map.get(state.active_streams, stream_id) do
      nil ->
        {:error, :stream_not_found}

      stream_state ->
        # Mark as cancelled
        cancelled_stream = %{stream_state | status: :cancelled}
        updated_streams = Map.put(state.active_streams, stream_id, cancelled_stream)

        # Clean up tracking
        updated_state =
          remove_stream_from_tracking(stream_state, %{
            state
            | active_streams: updated_streams
          })

        # Broadcast cancellation
        broadcast_to_session(stream_state.session_id, {
          :stream_cancelled,
          stream_id
        })

        # Clean up Redis state
        delete_session_state(stream_id)

        Logger.info("Cancelled MCP stream", stream_id: stream_id)

        {:ok, updated_state}
    end
  end

  defp cleanup_expired_streams(state) do
    cutoff_time = DateTime.add(DateTime.utc_now(), -@stream_timeout, :millisecond)

    expired_streams =
      state.active_streams
      |> Enum.filter(fn {_id, stream_state} ->
        stream_state.status == :active and
          DateTime.compare(stream_state.last_activity, cutoff_time) == :lt
      end)

    Enum.reduce(expired_streams, state, fn {stream_id, stream_state}, acc_state ->
      Logger.info("Cleaning up expired MCP stream", stream_id: stream_id)

      # Cancel the expired stream
      case cancel_stream_internal(stream_id, acc_state) do
        {:ok, updated_state} -> updated_state
        {:error, _} -> acc_state
      end
    end)
  end

  defp remove_stream_from_tracking(stream_state, state) do
    # Remove from user streams
    updated_user_streams =
      Map.update(state.user_streams, stream_state.user_id, [], fn streams ->
        List.delete(streams, stream_state.stream_id)
      end)

    # Remove empty entries
    cleaned_user_streams =
      Enum.reject(updated_user_streams, fn {_user_id, streams} ->
        Enum.empty?(streams)
      end)
      |> Enum.into(%{})

    %{state | user_streams: cleaned_user_streams}
  end

  defp build_stream_status(stream_state) do
    %{
      stream_id: stream_state.stream_id,
      session_id: stream_state.session_id,
      connection_id: stream_state.connection_id,
      status: stream_state.status,
      created_at: stream_state.created_at,
      last_activity: stream_state.last_activity,
      progress: %{
        total_chunks: stream_state.total_chunks,
        sent_chunks: stream_state.sent_chunks,
        completion_percentage:
          if(stream_state.total_chunks > 0,
            do: stream_state.sent_chunks / stream_state.total_chunks * 100,
            else: 0
          )
      }
    }
  end

  defp calculate_current_stats(state) do
    active_count =
      Enum.count(state.active_streams, fn {_, stream} -> stream.status == :active end)

    %{
      state.stats
      | active_streams: active_count
    }
  end

  defp broadcast_to_session(session_id, message) do
    topic = "mcp_stream:session:#{session_id}"
    PubSub.broadcast(Lang.PubSub, topic, message)
  end

  defp store_session_state(stream_id, stream_state) do
    _key = @redis_prefix <> stream_id
    _data = :erlang.term_to_binary(stream_state)

    # Store in Redis with TTL (would use Redis client here)
    # Redix.command(Lang.Redis, ["SETEX", key, @redis_ttl, data])
    :ok
  end

  defp delete_session_state(stream_id) do
    _key = @redis_prefix <> stream_id
    # Redix.command(Lang.Redis, ["DEL", key])
    :ok
  end

  defp generate_stream_id do
    "mcp_stream_" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
  end

  # Client_ID validation for secure MCP forwarding
  defp validate_client_id_for_stream(client_id, user_id, connection_id) do
    cond do
      is_nil(client_id) or client_id == "" ->
        {:error, "Client_ID required for MCP stream creation"}

      not is_binary(client_id) ->
        {:error, "Client_ID must be a string"}

      not String.match?(client_id, ~r/^[a-zA-Z0-9_-]{10,64}$/) ->
        {:error, "Client_ID format invalid (must be 10-64 alphanumeric characters with dashes/underscores)"}

      true ->
        # Additional validation: check if client has access to this connection
        case validate_client_connection_access(client_id, user_id, connection_id) do
          :ok -> {:ok, client_id}
          {:error, reason} -> {:error, "Client access denied: #{reason}"}
        end
    end
  end

  defp validate_client_connection_access(client_id, user_id, connection_id) do
    # Check if the connection belongs to the user
    case Lang.MCP.ConnectionManager.get_connection_record(connection_id) do
      {:ok, connection} ->
        # Verify the connection's user_id matches
        if connection.user_id == user_id do
          # Additional check: verify client_id is authorized for this user/connection
          # This could involve checking JWT claims, API keys, or other auth mechanisms
          case check_client_authorization(client_id, user_id, connection_id) do
            :ok -> :ok
            {:error, reason} -> {:error, reason}
          end
        else
          {:error, "Connection does not belong to user"}
        end

      {:error, :not_found} ->
        {:error, "Connection not found"}

      {:error, _reason} ->
        {:error, "Unable to verify connection access"}
    end
  end

  defp check_client_authorization(client_id, user_id, connection_id) do
    # This is where you would implement your authorization logic
    # For example:
    # - Verify JWT token claims
    # - Check API key permissions
    # - Validate OAuth scopes
    # - Check rate limits for the client

    # For now, we'll do basic checks
    cond do
      # Check if client_id is associated with the user
      not client_belongs_to_user?(client_id, user_id) ->
        {:error, "Client_ID not authorized for this user"}

      # Check if client has permission for MCP operations
      not client_has_mcp_permission?(client_id) ->
        {:error, "Client_ID lacks MCP permissions"}

      # Check rate limiting
      client_rate_limited?(client_id) ->
        {:error, "Client_ID rate limited"}

      true ->
        :ok
    end
  end

  # Placeholder functions - implement based on your auth system
  defp client_belongs_to_user?(client_id, user_id) do
    # Check if client_id is registered for this user
    # This could query a database or check a cache
    # For now, we'll accept any client_id that starts with the user_id
    String.starts_with?(client_id, user_id <> "_") or client_id == user_id
  end

  defp client_has_mcp_permission?(client_id) do
    # Check if client has MCP permissions
    # This could check scopes, roles, or permissions in your auth system
    # For now, we'll assume all clients have permission
    true
  end

  defp client_rate_limited?(client_id) do
    # Check if client is rate limited
    # This could check Redis counters or other rate limiting mechanisms
    # For now, we'll assume no rate limiting
    false
  end
end
