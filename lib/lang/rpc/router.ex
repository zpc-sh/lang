defmodule Lang.RPC.Router do
  @moduledoc false
  require Logger

  # Minimal dispatcher; extend as handlers are implemented
  def dispatch(_ctx, "rpc.ping", _params) do
    {:ok, %{pong: true, ts: DateTime.utc_now() |> DateTime.to_iso8601()}}
  end

  def dispatch(ctx, "rpc.initialize", params) do
    api_key_id = ctx[:api_key_id]
    limits = Application.get_env(:lang, :rpc_limits, %{})
    client = Map.get(params, "client", %{})

    capabilities = %{
      service: "lang",
      version: Application.spec(:lang, :vsn) |> to_string(),
      methods: [
        "rpc.ping",
        "rpc.initialize",
        "rpc.shutdown",
        # placeholders for future filesystem and analysis methods
        "lang.fs.scan",
        "lang.fs.search",
        "lang.fs.search_code",
        "lang.fs.preview"
      ],
      limits: limits,
      auth: %{api_key_id: api_key_id}
    }

    {:ok, %{capabilities: capabilities, client: client}}
  end

  def dispatch(_ctx, "rpc.shutdown", _params) do
    {:ok, %{ok: true}}
  end

  # Filesystem preview via FSScanner NIF
  def dispatch(ctx, "lang.fs.preview", %{"path" => path} = params) when is_binary(path) do
    with :ok <- can_proceed?(ctx, "lang.fs.preview") do
      max_lines = Map.get(params, "max_lines", 50)
      case Lang.Native.FSScanner.preview(path, max_lines: max_lines) do
        {:ok, lines} ->
          _ = track_usage(ctx, "lang.fs.preview")
          {:ok, %{path: path, lines: lines, max_lines: max_lines}}

        {:error, reason} ->
          {:error, -32002, "Preview failed", %{reason: inspect(reason)}}
      end
    end
  end

  def dispatch(_ctx, "lang.fs.preview", _), do: {:error, -32602, "Invalid params", %{required: ["path"]}}

  # Filesystem scan via FSScanner NIF
  def dispatch(ctx, "lang.fs.scan", %{"path" => path} = params) when is_binary(path) do
    with :ok <- can_proceed?(ctx, "lang.fs.scan") do
    max_depth = Map.get(params, "max_depth", 10)
    include_hidden = Map.get(params, "include_hidden", false)
    include_globs = Map.get(params, "include_globs", [])
    exclude_globs = Map.get(params, "exclude_globs", [])
    max_file_size_bytes = Map.get(params, "max_file_size_bytes", 0)

    opts = [
      max_depth: max_depth,
      include_hidden: include_hidden,
      include_globs: include_globs,
      exclude_globs: exclude_globs,
      max_file_size_bytes: max_file_size_bytes,
      stats: true
    ]

    case Lang.Native.FSScanner.scan(path, opts) do
      {:ok, %{tree: tree, stats: stats}} -> {:ok, %{path: path, tree: tree, stats: stats}}
      {:ok, %{tree: tree}} -> {:ok, %{path: path, tree: tree}}
      {:error, reason} -> {:error, -32003, "Scan failed", %{reason: inspect(reason)}}
    end
    |> tap_ok(fn _ -> track_usage(ctx, "lang.fs.scan") end)
    end
  end

  def dispatch(_ctx, "lang.fs.scan", _), do: {:error, -32602, "Invalid params", %{required: ["path"]}}

  # Filesystem regex search via FSScanner (ripgrep-backed)
  def dispatch(ctx, "lang.fs.search", %{"root_path" => root, "pattern" => pattern} = params)
      when is_binary(root) and is_binary(pattern) do
    with :ok <- can_proceed?(ctx, "lang.fs.search") do
    max_results = Map.get(params, "max_results", 100)
    context_lines = Map.get(params, "context_lines", 2)
    case_sensitive = Map.get(params, "case_sensitive", false)

    case Lang.Native.FSScanner.search(root, pattern,
           max_results: max_results,
           context_lines: context_lines,
           case_sensitive: case_sensitive
         ) do
      {:ok, results} -> {:ok, %{root_path: root, results: results}}
      {:error, reason} -> {:error, -32004, "Search failed", %{reason: inspect(reason)}}
    end
    |> tap_ok(fn _ -> track_usage(ctx, "lang.fs.search") end)
    end
  end

  def dispatch(_ctx, "lang.fs.search", _),
    do: {:error, -32602, "Invalid params", %{required: ["root_path", "pattern"]}}

  # Filesystem code search via tree-sitter
  def dispatch(ctx, "lang.fs.search_code", %{"root_path" => root, "language" => lang, "pattern" => patt} = params)
      when is_binary(root) and is_binary(lang) and is_binary(patt) do
    with :ok <- can_proceed?(ctx, "lang.fs.search_code") do
    max_results = Map.get(params, "max_results", 100)

    case Lang.Native.FSScanner.search_code(root, lang, patt, max_results: max_results) do
      {:ok, matches} -> {:ok, %{root_path: root, language: lang, matches: matches}}
      {:error, reason} -> {:error, -32005, "Code search failed", %{reason: inspect(reason)}}
    end
    |> tap_ok(fn _ -> track_usage(ctx, "lang.fs.search_code") end)
    end
  end

  # MCP RPC stubs
  def dispatch(ctx, "mcp.connection.create", params) when is_map(params) do
    with :ok <- can_proceed?(ctx, "mcp.connection.create") do
      Lang.RPC.MCPHandlers.connection_create(ctx, params)
      |> tap_ok(fn _ -> track_usage(ctx, "mcp.connection.create") end)
    end
  end

  def dispatch(ctx, "mcp.connection.status", %{"connection_id" => _} = params) do
    with :ok <- can_proceed?(ctx, "mcp.connection.status") do
      Lang.RPC.MCPHandlers.connection_status(ctx, params)
      |> tap_ok(fn _ -> track_usage(ctx, "mcp.connection.status") end)
    end
  end

  def dispatch(ctx, "mcp.connection.destroy", %{"connection_id" => _} = params) do
    with :ok <- can_proceed?(ctx, "mcp.connection.destroy") do
      Lang.RPC.MCPHandlers.connection_destroy(ctx, params)
      |> tap_ok(fn _ -> track_usage(ctx, "mcp.connection.destroy") end)
    end
  end

  def dispatch(_ctx, "lang.fs.search_code", _),
    do: {:error, -32602, "Invalid params", %{required: ["root_path", "language", "pattern"]}}

  # Example of streaming using the channel pid
  def dispatch(%{channel_pid: pid} = _ctx, "rpc.stream_example", params) do
    request_id = Map.get(params, "request_id") ||
      ("ex-" <> Integer.to_string(:erlang.unique_integer([:positive])) <> "-" <> Integer.to_string(:erlang.monotonic_time()))

    # Store initial state (ephemeral)
    _ = Lang.RPC.SessionStore.put(request_id, %{status: "started"}, 300)

    Task.start(fn ->
      for i <- 1..3 do
        send(pid, {:rpc_stream, request_id, {:chunk, %{n: i, message: "hello"}}})
        _ = Lang.RPC.SessionStore.touch(request_id, 300)
        Process.sleep(50)
      end
      _ = Lang.RPC.SessionStore.put(request_id, %{status: "completed"}, 60)
      send(pid, {:rpc_stream_completed, request_id})
    end)

    {:ok, %{stream_id: request_id}}
  end

  def dispatch(_ctx, method, _params) when is_binary(method) do
    {:error, -32601, "Method not found", %{method: method}}
  end

  # Internal helpers
  defp can_proceed?(%{organization: %{id: org_id}}, _method) when not is_nil(org_id) do
    case Lang.Billing.can_make_request?(org_id) do
      {true, _meta} -> :ok
      {false, %{error: :limit_exceeded}} -> {:error, -32010, "Usage limit exceeded", %{organization_id: org_id}}
      {false, meta} -> {:error, -32011, "Billing check failed", %{details: meta}}
      other ->
        require Logger
        Logger.warning("Unexpected billing check result", result: other)
        :ok
    end
  end
  defp can_proceed?(_ctx, _method), do: :ok

  defp track_usage(%{user: user, organization: org}, method) do
    try do
      Lang.Events.track_event(%{
        event_type: "api_call_made",
        user_id: user && user.id,
        organization_id: org && org.id,
        metadata: %{method: method}
      })
    rescue
      _ -> :ok
    end
  end
  defp track_usage(_, _), do: :ok

  defp tap_ok({:ok, result} = ok, fun) when is_function(fun, 1) do
    _ = fun.(result)
    ok
  end
  defp tap_ok(other, _fun), do: other
end

defmodule Lang.RPC.MCPHandlers do
  @moduledoc false
  require Logger

  def connection_create(ctx, params) do
    org_id = get_in(ctx, [:organization, :id])
    # Generate a connection id (aligns with resource validation)
    conn_id = "mcp_conn_" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)

    # Bill per-connection (metered) if org present
    if org_id, do: Lang.Billing.report_mcp_connection(org_id)

    # In a full impl: enqueue Broker connect here
    result = %{
      connection_id: conn_id,
      status: "connecting",
      session_id: Map.get(params, "session_id")
    }
    {:ok, result}
  end

  def connection_status(_ctx, %{"connection_id" => conn_id}) do
    # Stubbed status; integrate with MCP.Pool later
    {:ok, %{connection_id: conn_id, status: "connected"}}
  end

  def connection_destroy(ctx, %{"connection_id" => conn_id}) do
    org_id = get_in(ctx, [:organization, :id])
    # Track event; in full impl: Broker disconnect
    track_event(org_id, "mcp_connection_destroyed", %{connection_id: conn_id})
    {:ok, %{ok: true, connection_id: conn_id}}
  end

  defp track_event(nil, _type, _meta), do: :ok
  defp track_event(org_id, type, meta) do
    try do
      Lang.Events.track_event(%{event_type: type, organization_id: org_id, metadata: meta})
    rescue
      _ -> :ok
    end
  end
end
