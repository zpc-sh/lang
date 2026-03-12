defmodule Mix.Tasks.Lsp.Debug do
  use Mix.Task
  @shortdoc "Client debug harness: run a sequence of LSP calls and capture raw results"

  @moduledoc """
  Sends a small sequence of LSP JSON-RPC calls and prints results with timing.

      mix lsp.debug [--host 127.0.0.1] [--port 4001] [--file calls.json]

  If `--file` is provided, it should contain a JSON array of objects:
    [{"method":"rpc.ping","params":{}}, {"method":"folder/registry.getManifest","params":{...}}]
  Otherwise, defaults to: rpc.ping, rpc.capabilities, and optional Folder calls if env is set.
  """

  alias Lang.LSP.API

  @impl true
  def run(argv) do
    Mix.Task.run("loadpaths")
    {opts, _rest, _} = OptionParser.parse(argv, strict: [host: :string, port: :integer, file: :string, explain: :boolean])
    host = (opts[:host] || System.get_env("LSP_HOST") || "127.0.0.1") |> to_charlist()
    port = opts[:port] || env_int("LSP_PORT", 4001)

    calls =
      case opts[:file] do
        nil -> default_calls()
        path ->
          case File.read(path) do
            {:ok, bin} -> Jason.decode!(bin)
            {:error, e} -> Mix.raise("failed to read calls.json: #{inspect(e)}")
          end
      end

    # Optional identify notification for log correlation
    send_identify(host, port)

    Enum.each(calls, fn %{"method" => method, "params" => params} ->
      t0 = System.monotonic_time(:millisecond)
      res = API.call(method, params, host: host, port: port, timeout: 3_000)
      dt = System.monotonic_time(:millisecond) - t0
      line = %{method: method, duration_ms: dt, result: printable(res)}
      if opts[:explain], do: IO.puts(explain(method, res)), else: :ok
      IO.puts(Jason.encode!(line))
    end)
  end

  defp default_calls do
    base = [
      %{"method" => "rpc.ping", "params" => %{}},
      %{"method" => "rpc.capabilities", "params" => %{} },
      %{"method" => "rpc.serverInfo", "params" => %{} },
      %{"method" => "rpc.health", "params" => %{} }
    ]

    owner = System.get_env("FOLDER_OWNER")
    repo = System.get_env("FOLDER_REPO")
    ref = System.get_env("FOLDER_REFERENCE") || "latest"
    team = System.get_env("FOLDER_TEAM_ID")
    wid = System.get_env("FOLDER_WORKSPACE_ID")

    base ++
      (if owner && repo, do: [%{"method" => "folder/registry.getManifest", "params" => %{"owner" => owner, "repo" => repo, "reference" => ref}}], else: []) ++
      (if team && wid, do: [%{"method" => "folder/fs.list", "params" => %{"teamId" => team, "workspaceId" => wid, "path" => "."}}], else: [])
  end

  defp printable({:ok, data}), do: %{ok: true, data: shrink(data)}
  defp printable({:error, reason}), do: %{ok: false, error: inspect(reason)}

  defp shrink(map) when is_map(map) do
    Map.take(map, Enum.take(Map.keys(map), 12))
  end
  defp shrink(other), do: other

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

  defp explain("folder/registry.getManifest", {:ok, _}), do: "explain: manifest fetched (cache miss or hit); see metrics for cache/auth"
  defp explain("folder/registry.getBlob", {:ok, %{uri: _}}), do: "explain: blob redirected to URI (binary/large)"
  defp explain("folder/registry.getBlob", {:ok, %{content: _, mediaType: ct, size: sz}}), do: "explain: inlined content (#{ct}, #{sz} bytes)"
  defp explain(_m, {:ok, _}), do: "explain: ok"
  defp explain(_m, {:error, r}), do: "explain: error #{inspect(r)}"

  defp send_identify(host, port) do
    cid = System.get_env("LSP_CLIENT_ID") || "debug-" <> Integer.to_string(System.system_time(:millisecond))
    _ = Lang.LSP.Client.notify("lang/tester/identify", %{"clientId" => cid}, host: host, port: port)
    :ok
  end
end
