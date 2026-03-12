defmodule Lang.MCP.ConnectionManager do
  @moduledoc """
  LSP-facing connection helper for MCP.

  Bridges simplified LSP MCP calls to the secure MCP Broker/StreamBridge.

  Notes
  - This is intentionally minimal and does not assume HTTP auth context.
  - For LSP-triggered connections, a synthetic user/session is used unless
    provided via the `auth` map.
  - Broker persists best-effort via Ash; failures are contained.
  """

  require Logger
  alias Lang.MCP.Broker

  @type url :: String.t()
  @type auth :: map()
  @type connection_id :: String.t()

  @doc """
  Create an MCP connection from proxy envelope params and opts.

  Supports both URL-based and direct parameter-based connection creation.
  """
  @spec create_connection(map(), keyword() | map()) :: {:ok, map()} | {:error, term()}
  def create_connection(params, opts \\ []) do
    # Extract parameters
    url = Map.get(params, "url") || Map.get(params, "endpoint")
    server_type = Map.get(params, "server_type") || Map.get(params, "type")
    connection_params = Map.get(params, "connection_params", %{})
    auth = Map.get(params, "auth", %{})

    # Extract from opts
    user_id = get_opt(opts, :user_id) || Map.get(auth, "user_id") || synthetic_user()
    session_id = get_opt(opts, :session_id) || Map.get(auth, "session_id") || synthetic_session()
    client_id = get_opt(opts, :client_id) || Map.get(auth, "client_id")
    auth_session_id = Map.get(auth, "auth_session_id")

    Logger.debug("MCP ConnectionManager.create_connection",
      url: url,
      server_type: server_type,
      user_id: user_id,
      session_id: session_id,
      client_id: client_id
    )

    # Infer server type if not provided
    {inferred_type, config} =
      if server_type do
        {server_type, connection_params}
      else
        infer_server(url || "")
      end

    # Create connection via Broker
    case Broker.request_connection(inferred_type, user_id, session_id, config, auth_session_id) do
      {:ok, connection_id} ->
        # Persist connection record using Ash
        persist_connection(%{
          connection_id: connection_id,
          server_type: inferred_type,
          user_id: user_id,
          session_id: session_id,
          client_id: client_id,
          connection_params: config,
          status: :connecting
        })

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Destroy a previously created MCP connection with opts.
  """
  @spec destroy_connection(connection_id(), keyword() | map()) :: {:ok, map()} | {:error, term()}
  def destroy_connection(conn_id, opts) when is_binary(conn_id) do
    case Broker.disconnect(conn_id) do
      :ok ->
        # Update Ash record
        update_connection_status(conn_id, :disconnected)
        {:ok, %{destroyed: true, connection_id: conn_id}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Get MCP connection status with detailed information.
  """
  @spec get_connection_status(connection_id(), keyword() | map()) :: {:ok, map()} | {:error, term()}
  def get_connection_status(conn_id, opts \\ []) when is_binary(conn_id) do
    case Broker.get_connection_status(conn_id) do
      {:ok, broker_status} ->
        # Get additional info from Ash
        case get_connection_record(conn_id) do
          {:ok, record} ->
            {:ok, Map.merge(broker_status, %{
              connection_id: record.connection_id,
              server_type: record.connection_metadata["server_type"],
              created_at: record.inserted_at,
              last_activity: record.last_activity,
              status: record.status
            })}

          {:error, _} ->
            {:ok, broker_status}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Legacy function for backward compatibility
  @doc """
  Fetch MCP connection status from the Broker.
  """
  @spec get_status(connection_id()) :: {:ok, map()} | {:error, term()}
  def get_status(conn_id) when is_binary(conn_id) do
    get_connection_status(conn_id, [])
  end

  @doc """
  Destroy a previously created MCP connection (legacy).
  """
  @spec destroy_connection(connection_id()) :: :ok | {:error, term()}
  def destroy_connection(conn_id) when is_binary(conn_id) do
    case destroy_connection(conn_id, []) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  # -----------------------
  # Private helpers
  # -----------------------

  defp infer_server(url) do
    cond do
      is_file_url?(url) ->
        {"filesystem", %{"root_path" => normalize_file_url(url)}}

      is_git_url?(url) ->
        {"git", %{"repository_url" => url}}

      true ->
        {"web_search", %{"search_engine" => "duckduckgo", "hint" => url}}
    end
  end

  defp is_file_url?(url) do
    String.starts_with?(url, "file://") or String.starts_with?(url, "/") or String.starts_with?(url, "./")
  end

  defp normalize_file_url("file://" <> rest), do: "/" <> String.trim_leading(rest, "/")
  defp normalize_file_url(other), do: other

  defp is_git_url?(url) do
    String.ends_with?(url, ".git") or String.starts_with?(url, "git://") or
      String.starts_with?(url, "ssh://") or String.contains?(url, "@")
  end

  defp synthetic_user, do: "lsp_system"
  defp maybe_user_from_client(nil), do: nil
  defp maybe_user_from_client(cid) when is_binary(cid), do: "client:" <> cid
  defp synthetic_session do
    "lsp_session_" <> Base.encode16(:crypto.strong_rand_bytes(6), case: :lower)
  end

  # Ash integration helpers
  defp persist_connection(attrs) do
    try do
      connection_attrs = %{
        connection_id: attrs.connection_id,
        user_id: attrs.user_id,
        session_id: attrs.session_id,
        status: attrs.status,
        connection_params: attrs.connection_params,
        connection_metadata: %{
          "server_type" => attrs.server_type,
          "client_id" => attrs.client_id
        }
      }

      case Ash.create(Lang.MCP.Connection, connection_attrs) do
        {:ok, connection} ->
          Logger.debug("Persisted MCP connection", connection_id: connection.connection_id)
          {:ok, connection}

        {:error, changeset} ->
          Logger.warning("Failed to persist MCP connection",
            connection_id: attrs.connection_id,
            errors: inspect(changeset.errors)
          )
          # Don't fail the connection creation if persistence fails
          {:ok, attrs}
      end
    rescue
      e ->
        Logger.warning("Exception persisting MCP connection",
          connection_id: attrs.connection_id,
          error: Exception.message(e)
        )
        {:ok, attrs}
    end
  end

  defp update_connection_status(connection_id, status) do
    try do
      query = Lang.MCP.Connection |> Ash.Query.for_read(:by_connection_id, %{connection_id: connection_id})

      case Ash.read(query) do
        {:ok, [connection]} ->
          Ash.update!(connection, %{status: status})
          :ok

        {:ok, []} ->
          Logger.warning("Connection not found for status update", connection_id: connection_id)
          :ok

        {:error, reason} ->
          Logger.warning("Failed to update connection status",
            connection_id: connection_id,
            reason: inspect(reason)
          )
          :ok
      end
    rescue
      e ->
        Logger.warning("Exception updating connection status",
          connection_id: connection_id,
          error: Exception.message(e)
        )
        :ok
    end
  end

  defp get_connection_record(connection_id) do
    try do
      query = Lang.MCP.Connection |> Ash.Query.for_read(:by_connection_id, %{connection_id: connection_id})

      case Ash.read(query) do
        {:ok, [connection]} ->
          {:ok, connection}

        {:ok, []} ->
          {:error, :not_found}

        {:error, reason} ->
          Logger.warning("Failed to get connection record",
            connection_id: connection_id,
            reason: inspect(reason)
          )
          {:error, reason}
      end
    rescue
      e ->
        Logger.warning("Exception getting connection record",
          connection_id: connection_id,
          error: Exception.message(e)
        )
        {:error, :exception}
    end
  end

  defp get_opt(opts, key) do
    cond do
      is_list(opts) -> Keyword.get(opts, key)
      is_map(opts) -> Map.get(opts, key)
      true -> nil
    end
  end
end
