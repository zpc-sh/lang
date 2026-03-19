# Run with: elixir scripts/lsp_sandbox_harness.exs --method lang.think.review_code --json '{"code":"defmodule A do\n def hi, do: IO.inspect(:x)\nend","realtime":true}'
# Or: elixir scripts/lsp_sandbox_harness.exs --file priv/dev/lsp_calls.json

if Code.ensure_loaded?(Mix) do
  # Avoid Mix tasks; do not start Mix.PubSub or endpoints
  :ok
end

{:ok, _} = Application.ensure_all_started(:logger)

alias Lang.LSP.SandboxHarness
alias Lang.Native.FSScanner

defmodule Args do
  def parse(argv) do
    {opts, _, _} = OptionParser.parse(argv, strict: [method: :string, json: :string, file: :string, pubsub: :boolean])
    opts
  end
end

opts = Args.parse(System.argv())

# Optional in-process PubSub for streaming methods (no sockets used)
if opts[:pubsub] do
  _ = Process.whereis(Lang.PubSub) || (case Code.ensure_loaded?(Phoenix.PubSub) do
    true -> Phoenix.PubSub.start_link(name: Lang.PubSub)
    _ -> :ok
  end)
end

calls =
  cond do
    is_binary(opts[:method]) and is_binary(opts[:json]) ->
      params = case Jason.decode(opts[:json]) do
        {:ok, m} when is_map(m) -> m
        {:ok, _} -> %{}
        _ -> %{}
      end
      [%{"method" => opts[:method], "params" => params}]

    is_binary(opts[:file]) ->
      case FSScanner.preview(opts[:file], max_lines: 500_000) do
        {:ok, lines} ->
          content = Enum.join(List.wrap(lines), "\n")
          case Jason.decode(content) do
            {:ok, list} when is_list(list) -> list
            _ -> [%{"method" => "rpc.ping", "params" => %{}}]
          end
        _ -> [%{"method" => "rpc.ping", "params" => %{}}]
      end

    true ->
      [%{"method" => "rpc.ping", "params" => %{}}, %{"method" => "rpc.capabilities", "params" => %{}}]
  end

results = SandboxHarness.run_calls(calls)

Enum.each(results, fn r ->
  IO.puts(Jason.encode!(%{method: r.method, duration_ms: r.duration_ms, response: r.response}))
end)
