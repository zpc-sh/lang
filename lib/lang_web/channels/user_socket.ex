defmodule LangWeb.UserSocket do
  @moduledoc """
  UserSocket for MCP WebSocket channels with secure authentication.

  This socket handles WebSocket connections for MCP streaming communication,
  ensuring all connections are properly authenticated and authorized before
  allowing access to MCP resources.

  ## Security Model
  - All connections require valid authentication (API key or user session)
  - Rate limiting per user and connection type
  - Session isolation and access control
  - Comprehensive audit logging of all WebSocket events
  """

  use Phoenix.Socket

  require Logger
  alias Lang.Accounts.{User, ApiKey}
  alias Lang.Events
  alias LangWeb.AuthHelpers

  ## Channels
  # MCP streaming channels - authenticated access only
  channel "mcp:*", LangWeb.Api.V2.McpController

  # Socket authentication and transport configuration
  @impl true
  def connect(%{"token" => token}, socket, _connect_info) do
    case authenticate_token(token) do
      {:ok, user} ->
        socket =
          socket
          |> assign(:current_user, user)
          |> assign(:authenticated, true)
          |> assign(:connected_at, DateTime.utc_now())

        # Log successful connection
        Events.track_event(%{
          event_type: "mcp_websocket_connected",
          user_id: user.id,
          metadata: %{
            connected_at: DateTime.utc_now(),
            socket_id: socket.id
          }
        })

        Logger.info("MCP WebSocket connected", user_id: user.id, socket_id: socket.id)

        {:ok, socket}

      {:error, reason} ->
        Logger.warning("MCP WebSocket authentication failed",
          reason: reason,
          token: mask_token(token)
        )

        :error
    end
  end

  @impl true
  def connect(%{"api_key" => api_key}, socket, _connect_info) do
    case authenticate_api_key(api_key) do
      {:ok, user} ->
        socket =
          socket
          |> assign(:current_user, user)
          |> assign(:authenticated, true)
          |> assign(:auth_method, :api_key)
          |> assign(:connected_at, DateTime.utc_now())

        # Log successful API key connection
        Events.track_event(%{
          event_type: "mcp_websocket_api_key_connected",
          user_id: user.id,
          metadata: %{
            connected_at: DateTime.utc_now(),
            socket_id: socket.id,
            auth_method: "api_key"
          }
        })

        Logger.info("MCP WebSocket connected via API key",
          user_id: user.id,
          socket_id: socket.id
        )

        {:ok, socket}

      {:error, reason} ->
        Logger.warning("MCP WebSocket API key authentication failed",
          reason: reason,
          api_key: mask_token(api_key)
        )

        :error
    end
  end

  @impl true
  def connect(_params, _socket, _connect_info) do
    Logger.warning("MCP WebSocket connection attempt without authentication")
    :error
  end

  @impl true
  def id(socket) do
    case socket.assigns[:current_user] do
      %{id: user_id} -> "mcp_socket:#{user_id}"
      nil -> nil
    end
  end

  @impl true
  def handle_info({:disconnect, reason}, socket) do
    user_id = socket.assigns[:current_user][:id]

    # Log disconnection
    Events.track_event(%{
      event_type: "mcp_websocket_disconnected",
      user_id: user_id,
      metadata: %{
        reason: inspect(reason),
        socket_id: socket.id,
        connected_at: socket.assigns[:connected_at],
        disconnected_at: DateTime.utc_now(),
        session_duration: calculate_session_duration(socket)
      }
    })

    Logger.info("MCP WebSocket disconnected",
      user_id: user_id,
      reason: reason,
      socket_id: socket.id
    )

    {:noreply, socket}
  end

  ## Private Authentication Functions

  defp authenticate_token(token) do
    case AshAuthentication.Jwt.verify(token, User) do
      {:ok, %{"sub" => subject}} ->
        case AshAuthentication.subject_to_user(subject, User) do
          {:ok, user} ->
            {:ok, load_user_with_associations(user)}

          error ->
            error
        end

      {:error, reason} ->
        {:error, {:invalid_token, reason}}
    end
  end

  defp authenticate_api_key(api_key) do
    # Remove any "Bearer " prefix
    clean_key = String.replace_prefix(api_key, "Bearer ", "")

    require Ash.Query

    case ApiKey
         |> Ash.Query.filter(key == ^clean_key and status == :active)
         |> Ash.Query.load([:user])
         |> Ash.read_one() do
      {:ok, %{user: user}} when not is_nil(user) ->
        # Update last used timestamp for API key
        Task.start(fn ->
          ApiKey.update(%{id: api_key.id}, %{last_used_at: DateTime.utc_now()})
        end)

        {:ok, load_user_with_associations(user)}

      _ ->
        {:error, :invalid_api_key}
    end
  rescue
    error ->
      Logger.error("API key authentication error", error: inspect(error))
      {:error, :api_key_lookup_failed}
  end

  defp load_user_with_associations(user) do
    case User.by_id(user.id) |> Ash.Query.load([:organization]) |> Ash.read_one() do
      {:ok, loaded_user} -> loaded_user
      _ -> user
    end
  end

  defp mask_token(token) when is_binary(token) do
    case String.length(token) do
      len when len > 8 ->
        prefix = String.slice(token, 0, 4)
        suffix = String.slice(token, -4, 4)
        "#{prefix}***#{suffix}"

      _ ->
        "***"
    end
  end

  defp mask_token(_), do: "***"

  defp calculate_session_duration(socket) do
    case socket.assigns[:connected_at] do
      %DateTime{} = connected_at ->
        DateTime.diff(DateTime.utc_now(), connected_at, :second)

      _ ->
        0
    end
  end
end
