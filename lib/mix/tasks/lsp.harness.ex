defmodule Mix.Tasks.Lsp.Harness do
  use Mix.Task
  @shortdoc "Multi-client LSP harness simulating concurrent AI agents"

  @moduledoc """
  Simulates multiple concurrent AI agent clients connecting to the LANG LSP server.

      mix lsp.harness [--clients 5] [--iterations 3] [--host 127.0.0.1] [--port 4001] [--scenario read|write|conflict|mixed|format_rename]

  For each simulated client, the harness:
  - establishes a persistent LSP connection (initialize + initialized)
  - sends an identify notification with a unique Client_ID
  - opens a synthetic document and requests completion & hover
  - logs request timings and aggregates pass/fail results

  Scenarios:
  - read (default): completion + hover loops without edits
  - write: each client edits its own document each iteration
  - conflict: all clients concurrently edit the same shared document (racey)
  - mixed: mixes read operations with occasional writes

  This is designed to stress multi-client routing, per-client state, and
  optimistic concurrency concerns without relying on a real editor.
  """

  require Logger
  alias Lang.LSP.Harness

  @default_clients 5
  @default_iterations 3
  @default_scenario :read

  @impl true
  def run(argv) do
    Mix.Task.run("loadpaths")

    {opts, _rest, _} =
      OptionParser.parse(argv,
        strict: [clients: :integer, iterations: :integer, host: :string, port: :integer, scenario: :string, stress: :boolean]
      )

    host = (opts[:host] || System.get_env("LSP_HOST") || "127.0.0.1") |> to_charlist()
    port = opts[:port] || env_int("LSP_PORT", 4001)
    clients = opts[:clients] || @default_clients
    iterations = opts[:iterations] || @default_iterations
    scenario = parse_scenario(opts[:scenario])

    # Ensure application (and LSP Supervisor) is started in the current BEAM
    {:ok, _} = Application.ensure_all_started(:lang)

    Mix.shell().info("[lsp.harness] host=#{to_string(host)} port=#{port} clients=#{clients} iterations=#{iterations} scenario=#{scenario}")

    summary = Harness.run(
      host: host,
      port: port,
      clients: clients,
      iterations: iterations,
      scenario: scenario,
      stress_rate_limit: opts[:stress] || false,
      emit: fn ev -> IO.puts(Jason.encode!(ev)) end
    )
    case summary do
      %{ok: ok, error: err} ->
        Mix.shell().info("[lsp.harness] summary ok=#{ok} error=#{err}")
        if err > 0, do: Mix.raise("harness: #{err} client(s) failed"), else: :ok
      other ->
        Mix.raise("unexpected harness summary: #{inspect(other)}")
    end
  end


  # summary printed by caller

  defp parse_scenario(nil), do: @default_scenario
  defp parse_scenario(str) when is_binary(str) do
    case String.downcase(str) do
      "read" -> :read
      "write" -> :write
      "conflict" -> :conflict
      "mixed" -> :mixed
      "format_rename" -> :format_rename
      _ -> @default_scenario
    end
  end

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
