defmodule LangWeb.Api.V2.McpController do
  @moduledoc """
  MCP API Controller - Secure HTTP endpoints for MCP broker access.

  This controller provides authenticated HTTP endpoints for MCP server access,
  ensuring all MCP communication goes through Lang's security layer with
  proper authentication, rate limiting, and audit logging.

  ## Security Model
  - All endpoints require authentication (API key or user session)
  - Rate limiting per user and MCP server type
  - Request/response validation and sanitization
  - Comprehensive audit logging
  - WebSocket endpoints for streaming communication

  ## Endpoints
  - POST /api/v2/mcp/connect - Request MCP server connection
  - GET /api/v2/mcp/status/:stream_id - Check connection status
  - DELETE /api/v2/mcp/disconnect/:stream_id - Clean disconnect
  - WebSocket /api/v2/mcp/stream/:stream_id - Streaming communication
  """

  use LangWeb, :controller
  use Phoenix.Channel
  alias LangWeb.Router.Helpers, as: Routes

  alias Lang.MCP.{Broker, StreamBridge, Security}
  alias Lang.Events
  alias LangWeb.AuthHelpers
  alias LangWeb.ApiError
  require Logger

  action_fallback LangWeb.Api.FallbackController

  # Request size limits
  # 1MB
  @max_request_size 1024 * 1024
  @connection_timeout :timer.seconds(30)

  ## HTTP Endpoints

  @doc """
  Request a secure MCP server connection.

  POST /api/v2/mcp/connect

  Request body:
  {
    "server_type": "filesystem",
    "config": {...},
    "session_id": "optional_session_id"
  }

  Response:
  {
    "connection_id": "mcp_conn_...",
    "stream_id": "mcp_stream_...",
    "status": "connected",
    "server_info": {...}
  }
  """
  def connect(conn, params) do
    {conn, auth_session_id} = AuthHelpers.get_or_put_auth_session_id(conn)

    with {:ok, request} <- validate_connect_request(params),
         {:ok, user_id} <- get_authenticated_user_id(conn),
         :ok <- check_rate_limit(user_id, "mcp_connect"),
         {:ok, connection_id} <- create_mcp_connection(request, user_id, auth_session_id),
         {:ok, stream_id} <- create_streaming_bridge(connection_id, user_id, request) do
      # Log successful connection
      Events.track_event(%{
        event_type: "mcp_connection_requested",
        user_id: user_id,
        metadata: %{
          server_type: request["server_type"],
          connection_id: connection_id,
          stream_id: stream_id,
          session_id: request["session_id"],
          auth_session_id: auth_session_id
        }
      })

      response = %{
        "@context" => "https://lang.nulity.com/context/mcp",
        connection_id: connection_id,
        stream_id: stream_id,
        status: "connected",
        server_info: %{
          server_type: request["server_type"],
          created_at: DateTime.utc_now(),
          endpoints: %{
            status: ~p"/api/v2/mcp/status/#{stream_id}",
            disconnect_by_stream: ~p"/api/v2/mcp/disconnect/#{stream_id}",
            disconnect: ~p"/api/v2/mcp/disconnect/#{connection_id}",
            # clients join topic "mcp:#{stream_id}"
            websocket: ~p"/socket/websocket?vsn=2.0.0"
          }
        },
        topics: %{
          websocket: "mcp:#{stream_id}",
          session: "mcp_stream:session:#{request["session_id"]}"
        }
      }

      conn
      |> put_status(:created)
      |> json(response)
    else
      {:error, :rate_limited} ->
        ApiError.json(conn, :too_many_requests, "Rate limit exceeded for MCP connections")

      {:error, :server_type_not_allowed} ->
        ApiError.json(conn, :bad_request, "MCP server type not allowed", %{
          allowed: Lang.MCP.Security.allowed_server_types()
        })

      {:error, :user_connection_limit_exceeded} ->
        ApiError.json(conn, :forbidden, "Maximum MCP connections exceeded for user", %{
          max_connections: Broker.max_connections_per_user()
        })

      {:error, reason} ->
        Logger.warning("MCP connection failed", reason: reason, params: params)

        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Failed to create MCP connection", details: inspect(reason)})
    end
  end

  @doc """
  Get MCP connection and stream status.

  GET /api/v2/mcp/status/:stream_id

  Response:
  {
    "stream_id": "mcp_stream_...",
    "connection_status": "active",
    "stream_status": "streaming",
    "progress": {...},
    "stats": {...}
  }
  """
  def status(conn, %{"stream_id" => stream_id}) do
    with {:ok, user_id} <- get_authenticated_user_id(conn),
         {:ok, stream_status} <- StreamBridge.get_stream_status(stream_id),
         :ok <- verify_stream_access(stream_status, user_id) do
      conn_status = get_connection_status(stream_status.connection_id)

      response = %{
        "@context" => "https://lang.nulity.com/context/mcp",
        stream_id: stream_id,
        connection_id: stream_status.connection_id,
        connection_status: conn_status,
        stream_status: stream_status.status,
        server_type:
          case Broker.get_connection_status(stream_status.connection_id) do
            {:ok, %{server_type: st}} -> st
            _ -> nil
          end,
        progress: %{
          total_chunks: stream_status.total_chunks,
          sent_chunks: stream_status.sent_chunks,
          completion_percentage: calculate_completion_percentage(stream_status)
        },
        stats: %{
          created_at: stream_status.created_at,
          last_activity: stream_status.last_activity,
          session_id: stream_status.session_id
        },
        pool: Lang.MCP.Pool.get_stats(),
        endpoints: %{
          status: ~p"/api/v2/mcp/status/#{stream_id}",
          disconnect_by_stream: ~p"/api/v2/mcp/disconnect/#{stream_id}",
          disconnect: ~p"/api/v2/mcp/disconnect/#{stream_status.connection_id}"
        },
        topics: %{
          websocket: "mcp:#{stream_id}",
          session: "mcp_stream:session:#{stream_status.session_id}"
        }
      }

      json(conn, response)
    else
      {:error, :stream_not_found} ->
        ApiError.json(conn, :not_found, "MCP stream not found")

      {:error, :access_denied} ->
        ApiError.json(conn, :forbidden, "Access denied to MCP stream")

      {:error, reason} ->
        Logger.warning("Failed to get MCP status", stream_id: stream_id, reason: reason)

        ApiError.json(conn, :internal_server_error, "Failed to get stream status")
    end
  end

  @doc """
  Disconnect MCP connection and cleanup resources.

  DELETE /api/v2/mcp/disconnect/:stream_id

  Response:
  {
    "stream_id": "mcp_stream_...",
    "status": "disconnected",
    "cleanup": "complete"
  }
  """
  def disconnect(conn, %{"stream_id" => stream_id}) do
    {conn, auth_session_id} = AuthHelpers.get_or_put_auth_session_id(conn)

    with {:ok, user_id} <- get_authenticated_user_id(conn),
         {:ok, stream_status} <- StreamBridge.get_stream_status(stream_id),
         :ok <- verify_stream_access(stream_status, user_id),
         :ok <- StreamBridge.cancel_stream(stream_id),
         :ok <- Broker.disconnect(stream_status.connection_id) do
      # Log disconnection
      Events.track_event(%{
        event_type: "mcp_connection_disconnected",
        user_id: user_id,
        metadata: %{
          stream_id: stream_id,
          connection_id: stream_status.connection_id,
          duration_seconds: DateTime.diff(DateTime.utc_now(), stream_status.created_at),
          auth_session_id: auth_session_id
        }
      })

      response = %{
        "@context" => "https://lang.nulity.com/context/mcp",
        stream_id: stream_id,
        connection_id: stream_status.connection_id,
        status: "disconnected",
        cleanup: "complete"
      }

      json(conn, response)
    else
      {:error, :stream_not_found} ->
        ApiError.json(conn, :not_found, "MCP stream not found")

      {:error, :access_denied} ->
        ApiError.json(conn, :forbidden, "Access denied to MCP stream")

      {:error, reason} ->
        Logger.warning("Failed to disconnect MCP", stream_id: stream_id, reason: reason)

        ApiError.json(conn, :internal_server_error, "Failed to disconnect MCP connection")
    end
  end

  @doc """
  Disconnect by connection_id (preferred).

  DELETE /api/v2/mcp/disconnect/:connection_id
  """
  def disconnect(conn, %{"connection_id" => connection_id}) do
    with {:ok, user_id} <- get_authenticated_user_id(conn),
         {:ok, status} <- Broker.get_connection_status(connection_id),
         :ok <- verify_connection_access(status, user_id),
         :ok <- Broker.disconnect(connection_id) do
      Events.track_event(%{
        event_type: "mcp_connection_disconnected",
        user_id: user_id,
        metadata: %{
          connection_id: connection_id
        }
      })

      json(conn, %{
        "@context" => "https://lang.nulity.com/context/mcp",
        connection_id: connection_id,
        status: "disconnected",
        cleanup: "complete"
      })
    else
      {:error, :not_found} ->
        ApiError.json(conn, :not_found, "MCP connection not found")

      {:error, :access_denied} ->
        ApiError.json(conn, :forbidden, "Access denied to MCP connection")

      {:error, reason} ->
        Logger.warning("Failed to disconnect MCP", connection_id: connection_id, reason: reason)

        ApiError.json(conn, :internal_server_error, "Failed to disconnect MCP connection")
    end
  end

  ## WebSocket Channel for Streaming

  @doc """
  WebSocket channel for MCP streaming communication.

  Handles real-time bidirectional communication with MCP servers
  through the secure streaming bridge.
  """
  def join("mcp:" <> stream_id, _payload, socket) do
    with {:ok, user_id} <- get_socket_user_id(socket),
         {:ok, stream_status} <- StreamBridge.get_stream_status(stream_id),
         :ok <- verify_stream_access(stream_status, user_id) do
      # Subscribe to stream updates
      StreamBridge.subscribe_to_session(stream_status.session_id)

      updated_socket =
        socket
        |> Phoenix.Socket.assign(:stream_id, stream_id)
        |> Phoenix.Socket.assign(:user_id, user_id)
        |> Phoenix.Socket.assign(:connection_id, stream_status.connection_id)

      Logger.info("User joined MCP stream",
        stream_id: stream_id,
        user_id: user_id
      )

      {:ok, updated_socket}
    else
      {:error, reason} ->
        Logger.warning("Failed to join MCP stream",
          stream_id: stream_id,
          reason: reason
        )

        {:error, %{reason: "unauthorized"}}
    end
  end

  @doc """
  Handle incoming MCP requests through WebSocket.

  Message format:
  {
    "type": "mcp_request",
    "request": {...},
    "request_id": "optional_id"
  }
  """
  def handle_in("mcp_request", payload, socket) do
    stream_id = socket.assigns.stream_id
    user_id = socket.assigns.user_id

    with {:ok, mcp_request} <- validate_websocket_request(payload),
         :ok <- check_rate_limit(user_id, "mcp_request"),
         {:ok, _} <- StreamBridge.stream_mcp_request(stream_id, mcp_request) do
      # Log request
      Events.track_event(%{
        event_type: "mcp_websocket_request",
        user_id: user_id,
        metadata: %{
          stream_id: stream_id,
          method: Map.get(mcp_request, "method", "unknown"),
          request_id: Map.get(payload, "request_id")
        }
      })

      {:reply, {:ok, %{status: "processing", request_id: payload["request_id"]}}, socket}
    else
      {:error, :rate_limited} ->
        {:reply, {:error, %{reason: "rate_limited"}}, socket}

      {:error, reason} ->
        Logger.warning("MCP WebSocket request failed",
          stream_id: stream_id,
          reason: reason
        )

        {:reply, {:error, %{reason: inspect(reason)}}, socket}
    end
  end

  def handle_in("ping", _payload, socket) do
    {:reply, {:ok, %{type: "pong", timestamp: DateTime.utc_now()}}, socket}
  end

  def handle_in(event, payload, socket) do
    Logger.warning("Unknown WebSocket event",
      event: event,
      payload: payload,
      stream_id: socket.assigns.stream_id
    )

    {:reply, {:error, %{reason: "unknown_event", event: event}}, socket}
  end

  @doc """
  Handle MCP stream events from the bridge.
  """
  def handle_info({:stream_chunk, stream_id, chunk_data}, socket) do
    if socket.assigns.stream_id == stream_id do
      Phoenix.Channel.push(socket, "mcp_response", %{
        type: "chunk",
        stream_id: stream_id,
        data: chunk_data
      })
    end

    {:noreply, socket}
  end

  def handle_info({:stream_completed, stream_id}, socket) do
    if socket.assigns.stream_id == stream_id do
      Phoenix.Channel.push(socket, "mcp_response", %{
        type: "completed",
        stream_id: stream_id
      })
    end

    {:noreply, socket}
  end

  def handle_info({:stream_error, stream_id, error}, socket) do
    if socket.assigns.stream_id == stream_id do
      Phoenix.Channel.push(socket, "mcp_response", %{
        type: "error",
        stream_id: stream_id,
        error: inspect(error)
      })
    end

    {:noreply, socket}
  end

  def handle_info({:stream_cancelled, stream_id}, socket) do
    if socket.assigns.stream_id == stream_id do
      Phoenix.Channel.push(socket, "mcp_response", %{
        type: "cancelled",
        stream_id: stream_id
      })

      # Close the socket
      {:stop, :normal, socket}
    else
      {:noreply, socket}
    end
  end

  ## Private Helper Functions

  defp validate_connect_request(params) do
    with {:ok, server_type} <- get_required_param(params, "server_type"),
         {:ok, config} <- get_optional_param(params, "config", %{}),
         :ok <- validate_request_size(params),
         :ok <- Security.validate_server_type(server_type),
         {:ok, safe_config} <- Security.validate_mcp_config(server_type, config) do
      session_id = Map.get(params, "session_id", generate_session_id())

      {:ok,
       %{
         "server_type" => server_type,
         "config" => safe_config,
         "session_id" => session_id
       }}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_websocket_request(payload) do
    with {:ok, request} <- get_required_param(payload, "request"),
         :ok <- validate_request_size(request) do
      {:ok, request}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp get_required_param(params, key) do
    case Map.get(params, key) do
      nil -> {:error, {:missing_required_param, key}}
      value -> {:ok, value}
    end
  end

  defp get_optional_param(params, key, default) do
    {:ok, Map.get(params, key, default)}
  end

  defp validate_request_size(data) do
    size = byte_size(Jason.encode!(data))

    if size <= @max_request_size do
      :ok
    else
      {:error, {:request_too_large, size}}
    end
  rescue
    _ -> {:error, :invalid_request_format}
  end

  defp get_authenticated_user_id(conn) do
    case conn.assigns[:current_user] do
      %{id: user_id} -> {:ok, user_id}
      nil -> {:error, :not_authenticated}
    end
  end

  defp get_socket_user_id(socket) do
    case socket.assigns[:current_user] do
      %{id: user_id} -> {:ok, user_id}
      nil -> {:error, :not_authenticated}
    end
  end

  defp check_rate_limit(user_id, operation) do
    case Security.check_rate_limit(user_id, "mcp", operation) do
      :ok -> :ok
      {:error, :rate_limited} -> {:error, :rate_limited}
    end
  end

  defp create_mcp_connection(request, user_id, auth_session_id) do
    Broker.request_connection(
      request["server_type"],
      user_id,
      request["session_id"],
      request["config"],
      auth_session_id
    )
  end

  defp create_streaming_bridge(connection_id, user_id, request) do
    StreamBridge.create_stream(
      connection_id,
      user_id,
      request["session_id"]
    )
  end

  defp verify_stream_access(stream_status, user_id) do
    if stream_status.user_id == user_id do
      :ok
    else
      {:error, :access_denied}
    end
  end

  defp get_connection_status(connection_id) do
    case Broker.get_connection_status(connection_id) do
      {:ok, status} -> status.status
      {:error, _} -> "unknown"
    end
  end

  defp calculate_completion_percentage(stream_status) do
    if stream_status.total_chunks > 0 do
      Float.round(stream_status.sent_chunks / stream_status.total_chunks * 100, 1)
    else
      0.0
    end
  end

  defp generate_session_id do
    "mcp_session_" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
  end

  defp verify_connection_access(%{user_id: user_id}, user_id), do: :ok
  defp verify_connection_access(_status, _user_id), do: {:error, :access_denied}

  @doc """
  List active MCP connections for the authenticated user.

  GET /api/v2/mcp/connections
  """
  def list_active(conn, _params) do
    with {:ok, user_id} <- get_authenticated_user_id(conn),
         {:ok, connections} <- Broker.list_active(user_id) do
      # Enrich with endpoint URLs + topics for convenience
      enriched =
        Enum.map(connections, fn c ->
          Map.merge(c, %{
            endpoints: %{
              status: if(c.stream_id, do: ~p"/api/v2/mcp/status/#{c.stream_id}", else: nil),
              disconnect_by_stream:
                if(c.stream_id, do: ~p"/api/v2/mcp/disconnect/#{c.stream_id}", else: nil),
              disconnect: ~p"/api/v2/mcp/disconnect/#{c.connection_id}"
            },
            topics: %{
              websocket: if(c.stream_id, do: "mcp:#{c.stream_id}", else: nil),
              session: if(c.session_id, do: "mcp_stream:session:#{c.session_id}", else: nil)
            }
          })
        end)

      json(conn, %{
        "@context" => "https://lang.nulity.com/context/mcp",
        connections: enriched,
        pool: Lang.MCP.Pool.get_stats()
      })
    else
      {:error, :not_authenticated} ->
        ApiError.json(conn, :unauthorized, "Authentication required")

      {:error, reason} ->
        Logger.warning("Failed to list active MCP connections", reason: reason)

        ApiError.json(conn, :internal_server_error, "Failed to list active connections")
    end
  end
end
