defmodule Lang.LSP.Harness do
  @moduledoc """
  Core multi-client LSP harness used by Mix task and LiveView.

  Provides concurrent client simulation with pluggable event emission.
  """

  require Logger
  alias Lang.LSP.Client

  @type scenario :: :read | :write | :conflict | :mixed | :format_rename
  @type emit_fun :: (map() -> any())

  @spec run(keyword()) :: %{ok: non_neg_integer(), error: non_neg_integer()}
  def run(opts) do
    host = Keyword.fetch!(opts, :host)
    port = Keyword.fetch!(opts, :port)
    clients = Keyword.fetch!(opts, :clients)
    iterations = Keyword.fetch!(opts, :iterations)
    scenario = Keyword.get(opts, :scenario, :read)
    stress = Keyword.get(opts, :stress_rate_limit, false)
    emit = Keyword.get(opts, :emit, fn _ -> :ok end)

    1..clients
    |> Task.async_stream(
      fn i -> run_client(i, host, port, iterations, scenario, stress, emit) end,
      max_concurrency: min(clients, System.schedulers_online() * 2),
      timeout: :infinity
    )
    |> Enum.reduce(%{ok: 0, error: 0}, fn
      {:ok, :ok}, acc -> %{acc | ok: acc.ok + 1}
      {:ok, _}, acc -> %{acc | ok: acc.ok + 1}
      {:exit, _}, acc -> %{acc | error: acc.error + 1}
      {:error, _}, acc -> %{acc | error: acc.error + 1}
    end)
  end

  # --- client driver ---

  defp run_client(i, host, port, iterations, scenario, stress, emit) do
    client_id = "agent_#{i}_#{System.unique_integer([:positive])}"
    root = System.cwd!()

    case Client.connect(host: host, port: port, client_id: client_id, root_path: root, timeout: 5_000) do
      {:ok, conn} ->
        _ = notify_conn(conn, "lang/tester/identify", %{"clientId" => client_id})

        case scenario do
          :read -> run_read(conn, i, client_id, iterations, stress, emit)
          :write -> run_write(conn, i, client_id, iterations, emit)
          :conflict -> run_conflict(conn, i, client_id, iterations, emit)
          :mixed -> run_mixed(conn, i, client_id, iterations, emit)
          :format_rename -> run_format_rename(conn, i, client_id, iterations, emit)
        end

        Client.disconnect(conn)
        :ok

      {:error, reason} ->
        emit.(%{event: "client_error", client: i, client_id: client_id, error: inspect(reason)})
        {:error, reason}
    end
  end

  # --- scenarios ---

  defp run_read(conn, i, client_id, iterations, stress, emit) do
    uri = "file:///tmp/#{client_id}.ex"
    text = base_text(i)
    :ok = did_open(conn, uri, text)

    Enum.each(1..iterations, fn iter ->
      # Burst completions to stress rate limiter when enabled
      burst = if stress, do: String.to_integer(System.get_env("HARNESS_BURST") || "24"), else: 1
      for _ <- 1..burst do
        pos = %{"line" => 1, "character" => 20}
        case timed_request(conn, "textDocument/completion", %{"textDocument" => %{"uri" => uri}, "position" => pos}) do
          {:ok, dt} -> emit.(event(:completion, i, client_id, iter, dt))
          {:rate_limited, dt} -> emit.(%{event: "rate_limited", method: "textDocument/completion", client: i, client_id: client_id, iteration: iter, duration_ms: dt})
          {:error, dt, reason} -> emit.(%{event: "error", method: "textDocument/completion", client: i, client_id: client_id, iteration: iter, duration_ms: dt, reason: inspect(reason)})
        end
      end

      pos2 = %{"line" => 0, "character" => 15}
      case timed_request(conn, "textDocument/hover", %{"textDocument" => %{"uri" => uri}, "position" => pos2}) do
        {:ok, dt} -> emit!(emit, event(:hover, i, client_id, iter, dt))
        {:rate_limited, dt} -> emit!(emit, %{event: "rate_limited", method: "textDocument/hover", client: i, client_id: client_id, iteration: iter, duration_ms: dt})
        {:error, dt, reason} -> emit!(emit, %{event: "error", method: "textDocument/hover", client: i, client_id: client_id, iteration: iter, duration_ms: dt, reason: inspect(reason)})
      end
    end)
  end

  defp run_write(conn, i, client_id, iterations, emit) do
    uri = "file:///tmp/#{client_id}.ex"
    text = base_text(i)
    :ok = did_open(conn, uri, text)

    Enum.reduce(1..iterations, {text, 2}, fn iter, {cur, ver} ->
      new = cur <> "\n# client #{client_id} iter #{iter}"
      :ok = did_change(conn, uri, ver, new)

      case timed_request(conn, "textDocument/completion", %{"textDocument" => %{"uri" => uri}, "position" => %{"line" => 1, "character" => 20}}) do
        {:ok, dt} -> emit.(event(:completion, i, client_id, iter, dt))
        {:rate_limited, dt} -> emit.(%{event: "rate_limited", method: "textDocument/completion", client: i, client_id: client_id, iteration: iter, duration_ms: dt})
        {:error, dt, reason} -> emit.(%{event: "error", method: "textDocument/completion", client: i, client_id: client_id, iteration: iter, duration_ms: dt, reason: inspect(reason)})
      end
      {new, ver + 1}
    end)
  end

  defp run_conflict(conn, i, client_id, iterations, emit) do
    uri = System.get_env("HARNESS_SHARED_URI") || "file:///tmp/harness_shared.ex"
    text = base_text(:shared)
    :ok = did_open(conn, uri, text)

    Enum.reduce(1..iterations, {text, 2}, fn iter, {cur, ver} ->
      new = cur <> "\n# conflict from #{client_id} iter #{iter}"
      :ok = did_change(conn, uri, ver, new)

      case timed_request(conn, "textDocument/hover", %{"textDocument" => %{"uri" => uri}, "position" => %{"line" => 0, "character" => 10}}) do
        {:ok, dt} -> emit.(event(:hover, i, client_id, iter, dt))
        {:rate_limited, dt} -> emit.(%{event: "rate_limited", method: "textDocument/hover", client: i, client_id: client_id, iteration: iter, duration_ms: dt})
        {:error, dt, reason} -> emit.(%{event: "error", method: "textDocument/hover", client: i, client_id: client_id, iteration: iter, duration_ms: dt, reason: inspect(reason)})
      end
      {new, ver + 1}
    end)
  end

  defp run_mixed(conn, i, client_id, iterations, emit) do
    uri = "file:///tmp/#{client_id}.ex"
    text = base_text(i)
    :ok = did_open(conn, uri, text)

    Enum.reduce(1..iterations, {text, 2}, fn iter, {cur, ver} ->
      if rem(iter, 2) == 0 do
        new = cur <> "\n# mixed write #{iter}"
        :ok = did_change(conn, uri, ver, new)
        {new, ver + 1}
      else
        {cur, ver}
      end
    end)

    run_read(conn, i, client_id, max(1, div(iterations, 2)), false, emit)
  end

  defp run_format_rename(conn, i, client_id, iterations, emit) do
    uri = "file:///tmp/#{client_id}.ex"
    text = base_text(i)
    :ok = did_open(conn, uri, text)

    case timed_request(conn, "textDocument/formatting", %{"textDocument" => %{"uri" => uri}, "options" => %{"tabSize" => 2, "insertSpaces" => true}}, 4_000) do
      {:ok, dt} -> emit.(event(:formatting, i, client_id, 0, dt))
      {:rate_limited, dt} -> emit.(%{event: "rate_limited", method: "textDocument/formatting", client: i, client_id: client_id, iteration: 0, duration_ms: dt})
      {:error, dt, reason} -> emit.(%{event: "error", method: "textDocument/formatting", client: i, client_id: client_id, iteration: 0, duration_ms: dt, reason: inspect(reason)})
    end

    pos = %{"line" => 1, "character" => 8}
    new_name = "hello_#{i}"
    case timed_request(conn, "textDocument/rename", %{"textDocument" => %{"uri" => uri}, "position" => pos, "newName" => new_name}, 4_000) do
      {:ok, dt} -> emit.(event(:rename, i, client_id, 0, dt))
      {:rate_limited, dt} -> emit.(%{event: "rate_limited", method: "textDocument/rename", client: i, client_id: client_id, iteration: 0, duration_ms: dt})
      {:error, dt, reason} -> emit.(%{event: "error", method: "textDocument/rename", client: i, client_id: client_id, iteration: 0, duration_ms: dt, reason: inspect(reason)})
    end

    Enum.each(1..max(iterations - 1, 1), fn iter ->
      pos2 = %{"line" => 1, "character" => 20}
      case timed_request(conn, "textDocument/completion", %{"textDocument" => %{"uri" => uri}, "position" => pos2}) do
        {:ok, dt} -> emit.(event(:completion, i, client_id, iter, dt))
        {:rate_limited, dt} -> emit.(%{event: "rate_limited", method: "textDocument/completion", client: i, client_id: client_id, iteration: iter, duration_ms: dt})
        {:error, dt, reason} -> emit.(%{event: "error", method: "textDocument/completion", client: i, client_id: client_id, iteration: iter, duration_ms: dt, reason: inspect(reason)})
      end
    end)
  end

  # --- helpers ---

  defp did_open(conn, uri, text) do
    open = %{
      "textDocument" => %{"uri" => uri, "languageId" => "elixir", "version" => 1, "text" => text}
    }
    notify_conn(conn, "textDocument/didOpen", open)
  end

  defp did_change(conn, uri, version, new_text) do
    change = %{"textDocument" => %{"uri" => uri, "version" => version}, "contentChanges" => [%{"text" => new_text}]}
    notify_conn(conn, "textDocument/didChange", change)
  end

  defp notify_conn(%{socket: socket}, method, params) do
    payload = %{"jsonrpc" => "2.0", "method" => method} |> maybe_put_params(params)
    {:ok, json} = Jason.encode_to_iodata(payload)
    len = :erlang.iolist_size(json)
    header = ["Content-Length: ", Integer.to_string(len), "\r\n\r\n"]
    case :gen_tcp.send(socket, [header, json]) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp maybe_put_params(map, nil), do: map
  defp maybe_put_params(map, %{} = params) when map_size(params) == 0, do: map
  defp maybe_put_params(map, params), do: Map.put(map, "params", params)

  defp base_text(i) do
    mod = case i do
      :shared -> "Harness.Shared"
      _ -> "Harness.#{i}"
    end

    """
    defmodule #{mod} do
      def hello(name), do: IO.puts("hello \#{name}")
    end
    """ |> String.trim()
  end

  defp event(kind, client, client_id, iteration, duration_ms) do
    %{event: to_string(kind), client: client, client_id: client_id, iteration: iteration, duration_ms: duration_ms}
  end

  defp now_ms, do: System.monotonic_time(:millisecond)

  defp timed_request(conn, method, params, timeout \\ 3_000) do
    t0 = now_ms()
    case Client.request_with_connection(conn, method, params, timeout: timeout) do
      {:ok, _} -> {:ok, now_ms() - t0}
      {:error, %{"code" => -32001}} -> {:rate_limited, now_ms() - t0}
      {:error, reason} -> {:error, now_ms() - t0, reason}
    end
  end

  defp emit!(emit, map) do
    emit.(map)
    :ok
  end
end
