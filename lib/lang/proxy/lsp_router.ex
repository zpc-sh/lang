defmodule Lang.Proxy.LSPRouter do
  @moduledoc """
  LSP service dispatcher for the primary proxy.

  Strategy:
  - Local-first via Lang.Native.TreeParser for symbols
  - Optional enrichment via Lang.LSP.EngineAdapter
  - Merge/dedupe results
  """

  alias Lang.LSP.EngineAdapter
  alias Lang.Proxy.StreamBridge
  alias Lang.Proxy.Adapters.Telnet

  @type result :: {:ok, any()} | {:error, integer(), String.t(), map()}

  @doc """
  Dispatch a method within the LSP service.
  """
  @spec dispatch(String.t(), map(), keyword()) :: result()
  def dispatch("lsp.symbols", %{"file_path" => file_path} = params, opts) when is_binary(file_path) do
    local = local_symbols(file_path)
    # Attempt streaming if pipeline_id present and engine supports it
    _ = maybe_stream_symbols(params)
    engine = case EngineAdapter.symbols(params) do
      {:ok, list} -> list
      _ -> []
    end

    merged = merge_symbols(local, engine)

    # Optional persistence via Ash if requested
    persist? = Keyword.get(opts, :persist, false) || truthy?(get_in(params, ["persist"]))
    workspace_id = params["workspace_id"]
    if persist? and is_binary(workspace_id) do
      _ = Lang.Workspace.Service.ingest_symbols_async(workspace_id, file_path)
    end

    {:ok, %{symbols: merged}}
  end

  def dispatch("lsp.references", params, _opts) do
    _ = maybe_stream_references(params)
    case EngineAdapter.references(params) do
      {:ok, refs} -> {:ok, %{references: refs}}
      {:error, reason} -> {:error, -32002, "LSP references unavailable", %{reason: inspect(reason)}}
    end
  end

  def dispatch("lsp.definitions", params, _opts) do
    _ = maybe_stream_definitions(params)
    case EngineAdapter.definitions(params) do
      {:ok, defs} -> {:ok, %{definitions: defs}}
      {:error, reason} -> {:error, -32002, "LSP definitions unavailable", %{reason: inspect(reason)}}
    end
  end

  def dispatch("lsp.hover", params, _opts) do
    _ = maybe_stream_hover(params)
    case EngineAdapter.hover(params) do
      {:ok, hover} -> {:ok, %{hover: hover}}
      {:error, reason} -> {:error, -32002, "LSP hover unavailable", %{reason: inspect(reason)}}
    end
  end

  def dispatch("lsp.semantic_tokens", params, _opts) do
    _ = maybe_stream_semantic_tokens(params)
    case EngineAdapter.semantic_tokens(params) do
      {:ok, tokens} -> {:ok, %{semantic_tokens: tokens}}
      {:error, reason} -> {:error, -32002, "LSP semantic tokens unavailable", %{reason: inspect(reason)}}
    end
  end

  # SSH-based bootstrap for remote Engine/LSP
  def dispatch("lsp.bootstrap_ssh", params, _opts) do
    with {:ok, host} <- fetch_str(params, "host"),
         {:ok, user} <- fetch_str(params, "user"),
         {:ok, cmd} <- fetch_str(params, "cmd") do
      port = params["port"] || 22
      priv_key = params["priv_key"]
      known_hosts = params["known_hosts"]
      opts = [user: user, port: port] ++ (if is_binary(priv_key), do: [priv_key: priv_key], else: []) ++ (if is_binary(known_hosts), do: [known_hosts: known_hosts], else: [])

      case Lang.Proxy.Adapters.SSH.exec(host, cmd, opts) do
        {:ok, res} -> do_verify(params, %{ssh: res})
        {:error, :timeout} -> {:error, -32021, "ssh timeout", %{}}
        {:error, reason} -> {:error, -32022, "ssh error", %{reason: inspect(reason)}}
      end
    else
      {:error, {:bad_param, f}} -> {:error, -32602, "invalid params", %{field: f}}
      other -> {:error, -32602, "invalid params", %{reason: inspect(other)}}
    end
  end

  # Bootstrap an Engine/LSP instance via a bounded Telnet script, then optionally verify.
  # Params:
  # - host (required), port (required)
  # - script: list of %{send|expect} steps; if absent, use configured default
  # - verify: boolean (default false)
  # - verify_method: "symbols" | "definitions" | "hover" | "semantic_tokens" (default "symbols")
  # - verify_params: map passed to the EngineAdapter verify method
  def dispatch("lsp.bootstrap", params, _opts) do
    with {:ok, host} <- fetch_str(params, "host"),
         {:ok, port} <- fetch_int(params, "port") do
      script =
        case params["script"] do
          list when is_list(list) -> coerce_script(list)
          _ -> default_bootstrap_script()
        end

      case Telnet.run_script(host, port, script, timeout: 5_000) do
        {:ok, telnet_out} ->
          do_verify(params, telnet_out)

        {:error, :host_not_allowed} -> {:error, -32010, "host not allowed", %{}}
        {:error, :timeout} -> {:error, -32011, "telnet timeout", %{}}
        {:error, reason} -> {:error, -32012, "telnet error", %{reason: inspect(reason)}}
      end
    else
      {:error, {:bad_param, f}} -> {:error, -32602, "invalid params", %{field: f}}
      other -> {:error, -32602, "invalid params", %{reason: inspect(other)}}
    end
  end

  def dispatch(other, _params, _opts), do: {:error, -32601, "Method not found", %{method: other}}

  # --- local-first symbol extraction ---
  defp local_symbols(file_path) do
    case Lang.Native.TreeParser.extract_symbols(file_path) do
      {:ok, syms} when is_list(syms) -> Enum.map(syms, &normalize_local_symbol(&1, file_path))
      _ -> []
    end
  end

  defp normalize_local_symbol(sym, file_path) do
    name = to_string(sym["name"] || sym[:name] || "")
    kind = to_string(sym["symbol_type"] || sym[:symbol_type] || "") |> symbol_kind()
    loc = sym["location"] || sym[:location] || %{}
    row = (loc["row"] || loc[:row] || 0)
    col = (loc["column"] || loc[:column] || 0)

    %{
      name: name,
      kind: kind,
      range: %{
        start: %{line: row, character: col},
        end: %{line: row, character: col}
      },
      file_path: file_path,
      uri: "file://" <> file_path,
      source: :local
    }
  end

  defp symbol_kind(<<>>), do: "function"
  defp symbol_kind(nil), do: "function"
  defp symbol_kind(k) when is_binary(k), do: String.downcase(k)
  defp symbol_kind(k) when is_atom(k), do: k |> Atom.to_string() |> String.downcase()

  # --- merging ---
  defp merge_symbols(local, engine) do
    (local ++ Enum.map(engine, &normalize_engine_symbol/1))
    |> Enum.reduce(%{}, fn s, acc -> Map.put(acc, symbol_key(s), s) end)
    |> Map.values()
  end

  defp normalize_engine_symbol(%{"name" => _} = s), do: normalize_engine_symbol(Map.new(s, fn {k, v} -> {String.to_atom(k), v} end))
  defp normalize_engine_symbol(s) when is_map(s) do
    name = to_string(s[:name] || "")
    kind = s[:kind] || s[:symbol_type] || "function"
    file_path = s[:file_path] || s[:path] || s[:uri] && strip_file_uri(s[:uri]) || ""
    range =
      case s[:range] do
        %{start: %{} = st, end: %{} = en} -> %{start: %{line: st[:line] || st["line"] || 0, character: st[:character] || st["character"] || 0}, end: %{line: en[:line] || en["line"] || 0, character: en[:character] || en["character"] || 0}}
        _ -> %{start: %{line: 0, character: 0}, end: %{line: 0, character: 0}}
      end

    %{
      name: name,
      kind: symbol_kind(kind),
      range: range,
      file_path: file_path,
      uri: s[:uri] || ("file://" <> file_path),
      source: :engine
    }
  end

  defp strip_file_uri("file://" <> rest), do: rest
  defp strip_file_uri(other), do: other

  defp symbol_key(%{file_path: fp, name: n, range: %{start: %{line: l, character: c}}, kind: k}) do
    {fp, n, l, c, k}
  end

  defp truthy?(v) when v in [true, "true", 1, "1"], do: true
  defp truthy?(_), do: false

  defp maybe_stream_symbols(%{"pipeline_id" => pid} = params) when is_binary(pid) do
    hop = hop_meta("lsp.symbols", params)
    cb = fn partial -> StreamBridge.hop_partial(pid, hop, partial) end
    case EngineAdapter.symbols_stream(params, cb) do
      :ok -> :ok
      _ -> :noop
    end
  end
  defp maybe_stream_symbols(_), do: :ok

  defp maybe_stream_references(%{"pipeline_id" => pid} = params) when is_binary(pid) do
    hop = hop_meta("lsp.references", params)
    cb = fn partial -> StreamBridge.hop_partial(pid, hop, partial) end
    case EngineAdapter.references_stream(params, cb) do
      :ok -> :ok
      _ -> :noop
    end
  end
  defp maybe_stream_references(_), do: :ok

  defp maybe_stream_definitions(%{"pipeline_id" => pid} = params) when is_binary(pid) do
    hop = hop_meta("lsp.definitions", params)
    cb = fn partial -> StreamBridge.hop_partial(pid, hop, partial) end
    case EngineAdapter.definitions_stream(params, cb) do
      :ok -> :ok
      _ -> :noop
    end
  end
  defp maybe_stream_definitions(_), do: :ok

  defp maybe_stream_hover(%{"pipeline_id" => pid} = params) when is_binary(pid) do
    hop = hop_meta("lsp.hover", params)
    cb = fn partial -> StreamBridge.hop_partial(pid, hop, partial) end
    case EngineAdapter.hover_stream(params, cb) do
      :ok -> :ok
      _ -> :noop
    end
  end
  defp maybe_stream_hover(_), do: :ok

  defp maybe_stream_semantic_tokens(%{"pipeline_id" => pid} = params) when is_binary(pid) do
    hop = hop_meta("lsp.semantic_tokens", params)
    cb = fn partial -> StreamBridge.hop_partial(pid, hop, partial) end
    case EngineAdapter.semantic_tokens_stream(params, cb) do
      :ok -> :ok
      _ -> :noop
    end
  end
  defp maybe_stream_semantic_tokens(_), do: :ok

  defp hop_meta(method, params) do
    base = %{service: :lsp, method: method}
    case params["hop_uid"] do
      uid when is_binary(uid) -> Map.put(base, :uid, uid)
      _ -> base
    end
  end

  defp fetch_str(params, key) do
    case params[key] do
      s when is_binary(s) and byte_size(s) > 0 -> {:ok, s}
      _ -> {:error, {:bad_param, key}}
    end
  end

  defp fetch_int(params, key) do
    case params[key] do
      i when is_integer(i) and i > 0 and i < 65536 -> {:ok, i}
      _ -> {:error, {:bad_param, key}}
    end
  end

  defp coerce_script(list) do
    list
    |> Enum.map(fn
      %{"send" => line} when is_binary(line) -> {:send, line}
      %{"expect" => pat} when is_binary(pat) -> {:expect, pat}
      %{"expect" => pat, "timeout" => t} when is_binary(pat) and is_integer(t) -> {:expect, pat, t}
      other -> raise ArgumentError, "invalid script step: #{inspect(other)}"
    end)
  end

  defp default_bootstrap_script do
    steps = Application.get_env(:lang, :lsp_bootstrap_script)
    if is_list(steps), do: coerce_script(steps), else: []
  end

  defp do_verify(params, telnet_out) do
    if truthy?(params["verify"]) do
      method = to_string(params["verify_method"] || "symbols")
      vparams = params["verify_params"] || %{}

      case call_verify(method, vparams) do
        {:ok, result} -> {:ok, %{bootstrap: telnet_out, verify: %{ok: true, result: result}}}
        {:error, reason} -> {:error, -32013, "verification failed", %{reason: inspect(reason), bootstrap: telnet_out}}
      end
    else
      {:ok, %{bootstrap: telnet_out}}
    end
  end

  defp call_verify("symbols", p), do: EngineAdapter.symbols(p)
  defp call_verify("definitions", p), do: EngineAdapter.definitions(p)
  defp call_verify("hover", p), do: EngineAdapter.hover(p)
  defp call_verify("semantic_tokens", p), do: EngineAdapter.semantic_tokens(p)
  defp call_verify(_, p), do: EngineAdapter.symbols(p)
end
