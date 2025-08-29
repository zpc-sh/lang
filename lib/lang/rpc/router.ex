defmodule Elixir.Lang.LSP.Lang.Rpc.Shutdown do
  @moduledoc "Clean shutdown"
  @behaviour Lang.LSP.Handler
  @lsp_method "lang.rpc.shutdown"

  @impl true
  def method, do: @lsp_method

  @impl true
  def handle(params, ctx) when is_map(params) and is_map(ctx) do
    # Extract shutdown options
    force = Map.get(params, "force", false)
    timeout_seconds = Map.get(params, "timeout_seconds", 30)
    reason = Map.get(params, "reason", "user_requested")

    Logger.info("RPC shutdown requested",
      force: force,
      timeout: timeout_seconds,
      reason: reason,
      context: ctx
    )

    # Perform graceful shutdown sequence
    case perform_shutdown(force, timeout_seconds, reason) do
      :ok ->
        {:ok,
         %{
           shutdown_initiated: true,
           force: force,
           timeout_seconds: timeout_seconds,
           reason: reason,
           initiated_at: DateTime.utc_now()
         }}

      {:error, reason} ->
        {:error, "Shutdown failed: #{reason}"}
    end
  end

  defp perform_shutdown(force, timeout_seconds, reason) do
    try do
      # Step 1: Stop accepting new connections
      stop_accepting_connections()

      # Step 2: Notify active clients about shutdown
      notify_clients_of_shutdown(timeout_seconds)

      # Step 3: Wait for active operations to complete (unless forced)
      unless force do
        wait_for_active_operations(timeout_seconds * 1000)
      end

      # Step 4: Stop core services in order
      shutdown_services(reason)

      # Step 5: Final cleanup
      perform_cleanup()

      # Step 6: Schedule application termination
      schedule_termination(if force, do: 1000, else: 5000)

      :ok
    rescue
      error ->
        Logger.error("Shutdown process failed", error: inspect(error))
        {:error, inspect(error)}
    end
  end

  defp stop_accepting_connections do
    # Stop LSP server from accepting new connections
    if pid = Process.whereis(Lang.LSP.Server) do
      GenServer.cast(pid, :stop_accepting_connections)
    end
  end

  defp notify_clients_of_shutdown(timeout_seconds) do
    # Send shutdown notification to all connected LSP clients
    notification = %{
      "jsonrpc" => "2.0",
      "method" => "window/showMessage",
      "params" => %{
        # Warning
        "type" => 2,
        "message" => "Server shutting down in #{timeout_seconds} seconds"
      }
    }

    if pid = Process.whereis(Lang.LSP.Server) do
      GenServer.cast(pid, {:broadcast_notification, notification})
    end
  end

  defp wait_for_active_operations(timeout_ms) do
    start_time = System.monotonic_time(:millisecond)

    wait_for_operations_loop(start_time, timeout_ms)
  end

  defp wait_for_operations_loop(start_time, timeout_ms) do
    elapsed = System.monotonic_time(:millisecond) - start_time

    if elapsed >= timeout_ms do
      Logger.warning("Timeout waiting for operations to complete")
      :timeout
    else
      case count_active_operations() do
        0 ->
          Logger.info("All operations completed successfully")
          :ok

        count ->
          Logger.info("Waiting for #{count} operations to complete...")
          Process.sleep(1000)
          wait_for_operations_loop(start_time, timeout_ms)
      end
    end
  end

  defp count_active_operations do
    # Count active Oban jobs, LSP requests, etc.
    oban_count = count_active_oban_jobs()
    lsp_count = count_active_lsp_requests()

    oban_count + lsp_count
  end

  defp count_active_oban_jobs do
    try do
      case Oban.config() do
        %{repo: repo} ->
          import Ecto.Query

          query =
            from(j in Oban.Job,
              where: j.state in ["executing", "scheduled", "retryable"],
              select: count(j.id)
            )

          repo.one(query) || 0

        _ ->
          0
      end
    rescue
      _ -> 0
    end
  end

  defp count_active_lsp_requests do
    # This would need access to LSP server state
    # For now, return 0
    0
  end

  defp shutdown_services(reason) do
    Logger.info("Shutting down services", reason: reason)

    # Stop services in reverse dependency order
    services = [
      Lang.LSP.ClientPool,
      Lang.MCP.Pool,
      Lang.MCP.Broker,
      Lang.Orchestration.Master,
      Oban
    ]

    Enum.each(services, fn service ->
      if pid = Process.whereis(service) do
        Logger.info("Stopping service: #{service}")

        try do
          GenServer.stop(pid, reason, 5000)
        rescue
          error ->
            Logger.warning("Error stopping #{service}: #{inspect(error)}")
        end
      end
    end)
  end

  defp perform_cleanup do
    Logger.info("Performing final cleanup")

    # Clean up ETS tables
    cleanup_ets_tables()

    # Close database connections
    cleanup_database_connections()

    # Clear caches
    cleanup_caches()
  end

  defp cleanup_ets_tables do
    # Find and clean up application ETS tables
    [:rate_limit_cache, :scratch_storage, :agent_metrics]
    |> Enum.each(fn table ->
      if :ets.whereis(table) != :undefined do
        :ets.delete(table)
      end
    end)
  end

  defp cleanup_database_connections do
    try do
      if Process.whereis(Lang.Repo) do
        Ecto.Adapters.SQL.disconnect_all(Lang.Repo, 5000)
      end
    rescue
      error ->
        Logger.warning("Error cleaning up database connections: #{inspect(error)}")
    end
  end

  defp cleanup_caches do
    try do
      if Process.whereis(Lang.Redis) do
        Redix.command(Lang.Redis, ["FLUSHDB"])
      end
    rescue
      error ->
        Logger.warning("Error cleaning up Redis cache: #{inspect(error)}")
    end
  end

  defp schedule_termination(delay_ms) do
    Logger.info("Scheduling application termination in #{delay_ms}ms")

    spawn(fn ->
      Process.sleep(delay_ms)
      Logger.info("Terminating application")
      System.halt(0)
    end)
  end
end
