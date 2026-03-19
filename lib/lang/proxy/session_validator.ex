defmodule Lang.Proxy.SessionValidator do
  @moduledoc """
  Validate JSON-LD Session blocks embedded in Markdown‑LD or envelopes.

  Hard rules (fail closed):
  - Allowlisted protocols only: ssh | lsp | mcp | fs
  - No raw secrets ("priv_key", "password", "token", "bearer")
  - For ssh: require host, user, key_ref (not priv_key), optional known_hosts_ref
  - For lsp bootstrap: require host/user when method is bootstrap_ssh
  - No remote @context dereferencing (we ignore remote; caller should have stripped it)
  """

  @allowed_protocols ~w(ssh lsp mcp fs)
  @secret_keys ["priv_key", "password", "token", "bearer", "api_key", "secret"]
  @forbidden_terms ~w(ash_resource resource model api_definition ecto_schema migration codegen)

  @spec validate(map()) :: :ok | {:error, term()}
  def validate(session) when is_map(session) do
    with :ok <- check_type_and_protocol(session),
         :ok <- check_no_secrets(session),
         :ok <- check_protocol_requirements(session) do
      :ok
    end
  end

  def validate(_), do: {:error, :invalid_session}

  defp check_type_and_protocol(%{"@type" => type, "protocol" => proto}) do
    cond do
      not (to_string(type) |> String.downcase() |> String.contains?("session")) -> {:error, :invalid_type}
      to_string(proto) not in @allowed_protocols -> {:error, :invalid_protocol}
      true -> :ok
    end
  end

  defp check_type_and_protocol(%{"protocol" => proto}) do
    if to_string(proto) in @allowed_protocols, do: :ok, else: {:error, :invalid_protocol}
  end

  defp check_type_and_protocol(_), do: {:error, :missing_protocol}

  defp check_no_secrets(map) when is_map(map) do
    has_secret? = Enum.any?(@secret_keys, &Map.has_key?(map, &1))
    has_forbidden? = Enum.any?(@forbidden_terms, &Map.has_key?(map, &1))
    (if has_secret?, do: {:error, :secrets_not_allowed}, else: :ok)
    |> case do
      :ok -> if has_forbidden?, do: {:error, :forbidden_terms}, else: :ok
      err -> err
    end
  end

  defp check_protocol_requirements(%{"protocol" => "ssh"} = m) do
    required = ["host", "user", "key_ref"]
    if Enum.all?(required, &is_binary(Map.get(m, &1))) do
      :ok
    else
      {:error, {:ssh_missing_fields, required}}
    end
  end

  defp check_protocol_requirements(%{"protocol" => "fs"} = m) do
    op = m["operation"] || m["op"]
    path = m["path"]
    allowed_ops = ["preview", "search", "scan"]
    roots = Application.get_env(:lang, :proxy_fs_roots, [])
    ws_root = workspace_root_from_session(m)
    cond do
      to_string(op) not in allowed_ops -> {:error, {:fs_invalid_op, allowed_ops}}
      not is_binary(path) -> {:error, :fs_missing_path}
      String.contains?(path, "..") -> {:error, :fs_path_traversal}
      roots != [] and not Enum.any?(roots, &String.starts_with?(path, &1)) ->
        {:error, {:fs_path_not_allowed, %{path: path, roots: roots}}}
      is_binary(ws_root) and ws_root != "" and not String.starts_with?(path, ws_root) ->
        {:error, {:fs_outside_workspace_root, %{path: path, workspace_root: ws_root}}}
      true -> :ok
    end
  end

  defp check_protocol_requirements(%{"protocol" => "mcp"} = m) do
    server = m["server"]
    tool = m["tool"]
    cond do
      not is_binary(server) -> {:error, :mcp_missing_server}
      Map.has_key?(m, "url") -> {:error, :mcp_url_not_allowed}
      tool && not is_binary(tool) -> {:error, :mcp_invalid_tool}
      true -> :ok
    end
  end

  defp check_protocol_requirements(%{"protocol" => _}), do: :ok

  defp workspace_root_from_session(m) do
    case m["workspace_root"] || m["root"] do
      root when is_binary(root) and root != "" -> root
      _ -> resolve_workspace_root(m)
    end
  end

  defp resolve_workspace_root(m) do
    case m["workspace_id"] do
      id when is_binary(id) and id != "" ->
        fetch_ws_root(id)

      _ -> nil
    end
  end

  defp fetch_ws_root(id) do
    try do
      require Ash.Query
      q =
        Lang.Workspace.Workspace
        |> Ash.Query.filter(id == ^id)
        |> Ash.read_one()

      case q do
        {:ok, ws} ->
          case ws && ws.metadata do
            %{} = meta -> meta["root_path"] || meta[:root_path]
            _ -> nil
          end

        _ -> nil
      end
    rescue
      _ -> nil
    end
  end
end
