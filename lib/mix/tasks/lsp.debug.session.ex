defmodule Mix.Tasks.Lsp.Debug.Session do
  use Mix.Task
  @shortdoc "Run an LSP debug plan with assertions and summarize pass/fail"

  @moduledoc """
  Executes a JSON plan of LSP calls with simple assertions and prints a pass/fail summary.

      mix lsp.debug.session --plan scripts/lsp_debug_plan.sample.json [--host 127.0.0.1] [--port 4001]

  Plan format (JSON):
  {
    "calls": [
      {"method":"rpc.ping","params":{},
       "expect": {"ok": true}},

      {"method":"folder/registry.getManifest",
       "params": {"owner":"$FOLDER_OWNER","repo":"$FOLDER_REPO","reference":"$FOLDER_REFERENCE"},
       "expect": {"ok": true, "has_keys": ["manifestJson"]}}
    ]
  }

  Supported expectations:
  - ok: true|false — expects success or failure
  - has_keys: ["key1", ...] — for {:ok, map} results, require present keys
  """

  alias Lang.LSP.API

  @impl true
  def run(argv) do
    Mix.Task.run("loadpaths")
    {opts, _rest, _} = OptionParser.parse(argv, strict: [plan: :string, host: :string, port: :integer])
    plan_path = opts[:plan] || Mix.raise("--plan is required (path to JSON plan)")
    host = (opts[:host] || System.get_env("LSP_HOST") || "127.0.0.1") |> to_charlist()
    port = opts[:port] || env_int("LSP_PORT", 4001)

    plan = read_plan!(plan_path)
    calls = Map.get(plan, "calls") || []
    {passes, fails} =
      Enum.reduce(calls, {0, 0}, fn call, {p, f} ->
        method = Map.fetch!(call, "method")
        params = substitute_env(Map.get(call, "params", %{}))
        expect = Map.get(call, "expect", %{})

        t0 = now_ms()
        res = API.call(method, params, host: host, port: port, timeout: 5_000)
        dt = now_ms() - t0

        case assert(res, expect) do
          :ok ->
            IO.puts(Jason.encode!(%{method: method, duration_ms: dt, pass: true}))
            {p + 1, f}

          {:error, reason} ->
            IO.puts(Jason.encode!(%{method: method, duration_ms: dt, pass: false, error: reason_to_string(reason), result: printable(res)}))
            {p, f + 1}
        end
      end)

    Mix.shell().info("\nSummary: passes=#{passes} fails=#{fails}")
    if fails > 0, do: Mix.raise("debug session failed with #{fails} failing call(s)")
  end

  defp read_plan!(path) do
    case File.read(path) do
      {:ok, bin} -> Jason.decode!(bin)
      {:error, e} -> Mix.raise("failed to read plan: #{inspect(e)}")
    end
  end

  defp substitute_env(%{} = map) do
    map
    |> Enum.map(fn {k, v} -> {k, substitute_env(v)} end)
    |> Enum.into(%{})
  end
  defp substitute_env(list) when is_list(list), do: Enum.map(list, &substitute_env/1)
  defp substitute_env(val) when is_binary(val) do
    case Regex.run(~r/^\$(\w+)$/, val) do
      [_, var] -> System.get_env(var) || ""
      _ -> val
    end
  end
  defp substitute_env(other), do: other

  defp assert({:ok, data}, %{"ok" => true} = exp), do: assert_keys(data, exp)
  defp assert({:ok, _data}, %{"ok" => false}), do: {:error, :expected_error_got_ok}
  defp assert({:error, _}, %{"ok" => false}), do: :ok
  defp assert({:error, err}, %{"ok" => true}), do: {:error, {:unexpected_error, err}}
  defp assert({:ok, data}, exp), do: assert_keys(data, exp)
  defp assert(res, _), do: {:error, {:unknown_result, res}}

  defp assert_keys(data, %{"has_keys" => keys}) when is_list(keys) and is_map(data) do
    missing = Enum.reject(keys, &Map.has_key?(data, &1))
    if missing == [], do: :ok, else: {:error, {:missing_keys, missing}}
  end
  defp assert_keys(_data, _), do: :ok

  defp printable({:ok, map}) when is_map(map), do: Map.take(map, Enum.take(Map.keys(map), 12))
  defp printable(other), do: other

  defp reason_to_string({:missing_keys, ks}), do: "missing_keys:" <> Enum.join(ks, ",")
  defp reason_to_string({:unexpected_error, r}), do: "unexpected_error:" <> inspect(r)
  defp reason_to_string(r), do: inspect(r)

  defp now_ms, do: System.monotonic_time(:millisecond)

  defp env_int(var, default) do
    case System.get_env(var) do
      nil -> default
      val ->
        case Integer.parse(val) do
          {i, _} -> i
          _ -> default
        end
    end
  end
end

