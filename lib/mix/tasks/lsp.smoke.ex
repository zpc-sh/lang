defmodule Mix.Tasks.Lsp.Smoke do
  use Mix.Task
  @shortdoc "Local smoke test: start LSP server briefly and run lsp.doctor"

  @moduledoc """
  Starts the LANG LSP server in-process (TCP), runs `lsp.doctor`, and shuts down.

  Usage:
    mix lsp.smoke [--port 4001] [--duration 60]

  Notes:
  - This does NOT start Phoenix. It only starts the LSP GenServer.
  - Duration is a safety cap; the task stops the server as soon as checks pass.
  """

  @impl true
  def run(argv) do
    Mix.Task.run("loadpaths")
    {opts, _rest, _} = OptionParser.parse(argv, strict: [port: :integer, duration: :integer])
    port = opts[:port] || 4001
    duration = opts[:duration] || 60

    {:ok, _apps} = Application.ensure_all_started(:logger)
    # Ensure our application (and required deps) are started
    {:ok, _} = Application.ensure_all_started(:lang)

    # Optional telemetry sink for metrics file
    if path = System.get_env("LSP_METRICS_LOG") do
      _ = Lang.LSP.TelemetryFileSink.attach(path)
      Mix.shell().info("Telemetry sink attached → #{path}")
    end

    # Start LSP server (TCP only) supervised under current VM
    {:ok, pid} = Lang.LSP.Server.start_link(mode: :tcp, port: port)

    # Safety timer in case something hangs
    ref = Process.send_after(self(), :timeout, duration * 1000)

    try do
      # Small delay to allow the server to listen
      Process.sleep(200)

      # Run doctor against this instance
      Mix.Task.reenable("lsp.doctor")
      Mix.Task.run("lsp.doctor", ["--port", Integer.to_string(port)])

      Mix.shell().info("LSP smoke: OK")
    after
      # Cleanup timer and server
      Process.cancel_timer(ref)
      Process.exit(pid, :normal)
      :ok
    end
  catch
    :exit, {:timeout, _} -> Mix.raise("LSP smoke timed out")
  end
end
