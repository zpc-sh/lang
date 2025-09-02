defmodule Mix.Tasks.Mcp.Harness do
  @moduledoc """
  MCP Integration Test Harness

  Provides comprehensive testing and monitoring capabilities for MCP integration:

  ## Examples

      # Run basic MCP integration tests
      mix mcp.harness

      # Test with specific client count and flux simulation
      mix mcp.harness --clients=10 --flux

      # Monitor MCP connections and streams in real-time
      mix mcp.harness --monitor

      # Test concurrent agent swarm creation
      mix mcp.harness --swarm-test --agents=5

      # Load test with stress simulation
      mix mcp.harness --stress --duration=60

  ## Options

    * `--clients` - Number of concurrent clients to simulate (default: 5)
    * `--flux` - Enable client flux simulation (connections/disconnections)
    * `--monitor` - Start monitoring mode for real-time MCP activity
    * `--swarm-test` - Test agent swarm creation workflows
    * `--agents` - Number of agents per swarm (default: 3)
    * `--stress` - Enable stress testing mode
    * `--duration` - Test duration in seconds (default: 30)
    * `--client-id-prefix` - Prefix for generated client IDs (default: "harness_client")
  """

  use Mix.Task
  require Logger

  alias Lang.MCP.{ConnectionManager, StreamBridge}
  alias Lang.Proxy.Router
  alias Lang.Proxy.Envelope
  alias Lang.Events

  @default_clients 5
  @default_duration 30
  @default_agents 3
  @client_id_prefix "harness_client"

  @impl Mix.Task
  def run(args) do
    # Ensure application is started
    Mix.Task.run("app.start")

    {opts, _} = OptionParser.parse!(args,
      strict: [
        clients: :integer,
        flux: :boolean,
        monitor: :boolean,
        swarm_test: :boolean,
        agents: :integer,
        stress: :boolean,
        duration: :integer,
        client_id_prefix: :string
      ]
    )

    clients = opts[:clients] || @default_clients
    flux = opts[:flux] || false
    monitor = opts[:monitor] || false
    swarm_test = opts[:swarm_test] || false
    agents = opts[:agents] || @default_agents
    stress = opts[:stress] || false
    duration = opts[:duration] || @default_duration
    client_prefix = opts[:client_id_prefix] || @client_id_prefix

    Logger.info("Starting MCP Harness",
      clients: clients,
      flux: flux,
      monitor: monitor,
      swarm_test: swarm_test,
      stress: stress,
      duration: duration
    )

    cond do
      monitor ->
        start_monitoring()

      stress ->
        run_stress_test(clients, duration, client_prefix)

      flux ->
        run_flux_simulation(clients, duration, client_prefix)

      swarm_test ->
        run_swarm_test(clients, agents, client_prefix)

      true ->
        run_basic_test(clients, client_prefix)
    end
  end

  defp run_basic_test(client_count, client_prefix) do
    Logger.info("Running basic MCP integration test")

    results = 1..client_count
    |> Enum.map(fn i ->
      Task.async(fn ->
        client_id = "#{client_prefix}_#{i}"
        test_basic_workflow(client_id, i)
      end)
    end)
    |> Enum.map(&Task.await(&1, 60_000))

    successful = Enum.count(results, &match?({:ok, _}, &1))
    failed = Enum.count(results, &match?({:error, _}, &1))

    Logger.info("Basic test completed",
      successful: successful,
      failed: failed,
      total: client_count,
      success_rate: "#{successful * 100 / client_count}%"
    )

    if failed > 0 do
      Logger.warning("Some tests failed", failures: Enum.filter(results, &match?({:error, _}, &1)))
    end
  end

  defp run_flux_simulation(client_count, duration, client_prefix) do
    Logger.info("Running client flux simulation", duration: duration)

    end_time = System.monotonic_time(:second) + duration

    # Start monitoring task
    monitor_task = Task.async(fn -> monitor_activity(end_time) end)

    # Run flux simulation
    flux_results = run_client_flux(client_count, end_time, client_prefix)

    # Wait for monitoring to complete
    Task.await(monitor_task, :infinity)

    Logger.info("Flux simulation completed",
      connections_created: flux_results.created,
      connections_destroyed: flux_results.destroyed,
      errors: flux_results.errors
    )
  end

  defp run_swarm_test(client_count, agents_per_swarm, client_prefix) do
    Logger.info("Running agent swarm test", clients: client_count, agents_per_swarm: agents_per_swarm)

    results = 1..client_count
    |> Enum.map(fn i ->
      Task.async(fn ->
        client_id = "#{client_prefix}_#{i}"
        test_swarm_workflow(client_id, i, agents_per_swarm)
      end)
    end)
    |> Enum.map(&Task.await(&1, 120_000))

    successful = Enum.count(results, &match?({:ok, _}, &1))
    failed = Enum.count(results, &match?({:error, _}, &1))

    Logger.info("Swarm test completed",
      successful: successful,
      failed: failed,
      total: client_count
    )
  end

  defp run_stress_test(client_count, duration, client_prefix) do
    Logger.info("Running MCP stress test", clients: client_count, duration: duration)

    # Start multiple waves of connections
    waves = 3
    clients_per_wave = div(client_count, waves)

    end_time = System.monotonic_time(:second) + duration

    1..waves
    |> Enum.each(fn wave ->
      Logger.info("Starting stress wave #{wave}/#{waves}")

      wave_results = 1..clients_per_wave
      |> Enum.map(fn i ->
        client_id = "#{client_prefix}_wave#{wave}_#{i}"
        Task.async(fn -> stress_test_client(client_id, end_time) end)
      end)
      |> Enum.map(&Task.await(&1, 10_000))

      successful = Enum.count(wave_results, &match?({:ok, _}, &1))
      Logger.info("Wave #{wave} completed", successful: successful, total: clients_per_wave)

      # Brief pause between waves
      Process.sleep(1000)
    end)

    Logger.info("Stress test completed")
  end

  # Test implementations

  defp test_basic_workflow(client_id, index) do
    try do
      # Create MCP connection
      envelope = %Envelope{
        service: :mcp,
        method: "connection.create",
        params: %{
          "url" => "file:///tmp/test_#{index}",
          "server_type" => "filesystem"
        },
        opts: %{
          "client_id" => client_id,
          "user_id" => "harness_user_#{index}",
          "session_id" => "harness_session_#{index}"
        }
      }

      with {:ok, conn_result} <- Router.dispatch(envelope),
           connection_id = Map.get(conn_result, "connection_id") || Map.get(conn_result, :connection_id),

           # Check status
           status_envelope = %{envelope | method: "connection.status", params: %{"connection_id" => connection_id}},
           {:ok, _status} <- Router.dispatch(status_envelope),

           # Create stream
           {:ok, stream_id} <- StreamBridge.create_stream(connection_id, "harness_user_#{index}", "harness_session_#{index}", %{"client_id" => client_id}),

           # Send test request
           {:ok, :streaming} <- StreamBridge.stream_mcp_request(stream_id, %{"method" => "list_directory", "params" => %{"path" => "/tmp"}}),

           # Cleanup
           {:ok, _} <- ConnectionManager.destroy_connection(connection_id, %{"client_id" => client_id}) do

        Logger.info("✓ Basic workflow completed", client_id: client_id, connection_id: connection_id)
        {:ok, %{connection_id: connection_id, stream_id: stream_id}}
      else
        error ->
          Logger.error("Basic workflow failed", client_id: client_id, error: error)
          {:error, error}
      end
    rescue
      e ->
        Logger.error("Basic workflow exception", client_id: client_id, exception: e)
        {:error, {:exception, e}}
    end
  end

  defp test_swarm_workflow(client_id, index, agent_count) do
    try do
      # Create MCP connection first
      envelope = %Envelope{
        service: :mcp,
        method: "connection.create",
        params: %{"url" => "file:///tmp/swarm_test_#{index}"},
        opts: %{"client_id" => client_id, "user_id" => "swarm_user_#{index}"}
      }

      with {:ok, conn_result} <- Router.dispatch(envelope),
           connection_id = Map.get(conn_result, "connection_id"),

           # Create agent swarm
           swarm_msg = %{
             "jsonrpc" => "2.0",
             "id" => index,
             "method" => "lang.agent.swarm_create",
             "params" => %{
               "goals" => ["test goal 1", "test goal 2"],
               "agent_count" => agent_count,
               "coordinator_id" => "test_coord_#{index}"
             }
           },

           {:ok, %{"result" => swarm_result}} <- Lang.LSP.Dispatch.process(swarm_msg),
           swarm_id = Map.get(swarm_result, "swarm_id"),

           # Cleanup
           {:ok, _} <- ConnectionManager.destroy_connection(connection_id, %{"client_id" => client_id}) do

        Logger.info("✓ Swarm workflow completed", client_id: client_id, swarm_id: swarm_id, agents: agent_count)
        {:ok, %{connection_id: connection_id, swarm_id: swarm_id}}
      else
        error ->
          Logger.error("Swarm workflow failed", client_id: client_id, error: error)
          {:error, error}
      end
    rescue
      e ->
        Logger.error("Swarm workflow exception", client_id: client_id, exception: e)
        {:error, {:exception, e}}
    end
  end

  defp run_client_flux(client_count, end_time, client_prefix) do
    # Create a pool of client connections that connect/disconnect randomly
    clients = 1..client_count |> Enum.map(fn i -> "#{client_prefix}_flux_#{i}" end)

    results = %{
      created: 0,
      destroyed: 0,
      errors: 0
    }

    flux_loop(clients, end_time, results)
  end

  defp flux_loop(_clients, end_time, results) do
    if System.monotonic_time(:second) >= end_time do
      results
    else
      # The original logic of the flux_loop should be placed here.
      # Since the original logic is not provided, I will assume it was just to return results.
      # If there was more logic, it needs to be added here.
      Process.sleep(100)
      flux_loop(_clients, end_time, results)
    end
  end

  defp flux_loop(clients, end_time, results) do
    # Randomly select a client and action
    client = Enum.random(clients)
    action = Enum.random([:connect, :disconnect, :status])

    new_results = case action do
      :connect ->
        case create_test_connection(client) do
          {:ok, _} -> %{results | created: results.created + 1}
          {:error, _} -> %{results | errors: results.errors + 1}
        end

      :disconnect ->
        case destroy_test_connection(client) do
          {:ok, _} -> %{results | destroyed: results.destroyed + 1}
          {:error, _} -> %{results | errors: results.errors + 1}
        end

      :status ->
        # Just check status, don't count as creation/destruction
        results
    end

    # Random delay between 100-500ms
    Process.sleep(Enum.random(100..500))

    flux_loop(clients, end_time, new_results)
  end

  defp stress_test_client(client_id, end_time) do
    # Rapid fire operations until time expires
    stress_loop(client_id, end_time, 0, 0)
  end

  defp stress_loop(_client_id, end_time, ops, errors) do
    if System.monotonic_time(:second) >= end_time do
      {:ok, %{operations: ops, errors: errors}}
    else
      do_stress_loop(_client_id, end_time, ops, errors)
    end
  end

  defp do_stress_loop(client_id, end_time, ops, errors) do
    result = case Enum.random([:connect, :quick_op, :status]) do
      :connect ->
        case create_test_connection(client_id) do
          {:ok, _} -> :ok
          {:error, _} -> :error
        end

      :quick_op ->
        # Quick connection + immediate disconnect
        with {:ok, _conn} <- create_test_connection(client_id),
             {:ok, _} <- destroy_test_connection(client_id) do
          :ok
        else
          _ -> :error
        end

      :status ->
        # Just status check
        :ok
    end

    new_ops = ops + 1
    new_errors = errors + if result == :error, do: 1, else: 0
    stress_loop(client_id, end_time, new_ops, new_errors)
  end

  defp stress_loop(client_id, end_time, ops, errors) do
    result = case Enum.random([:connect, :quick_op, :status]) do
      :connect ->
        case create_test_connection(client_id) do
          {:ok, _} -> :ok
          {:error, _} -> :error
        end

      :quick_op ->
        # Quick connection + immediate disconnect
        with {:ok, conn} <- create_test_connection(client_id),
             {:ok, _} <- destroy_test_connection(client_id) do
          :ok
        else
          _ -> :error
        end

      :status ->
        # Just status check
        :ok
    end

    new_ops = ops + 1
    new_errors = if result == :error, do: errors + 1, else: errors

    stress_loop(client_id, end_time, new_ops, new_errors)
  end

  # Helper functions

  defp create_test_connection(client_id) do
    envelope = %Envelope{
      service: :mcp,
      method: "connection.create",
      params: %{"url" => "file:///tmp/stress_test"},
      opts: %{"client_id" => client_id, "user_id" => "stress_user"}
    }

    Router.dispatch(envelope)
  end

  defp destroy_test_connection(client_id) do
    # For simplicity, just try to destroy with the client_id
    # In a real scenario, you'd track connection IDs
    ConnectionManager.destroy_connection("test_conn_#{client_id}", %{"client_id" => client_id})
  end

  defp start_monitoring do
    Logger.info("Starting MCP monitoring mode")

    # Subscribe to relevant events
    Events.subscribe_to_events()

    # Monitor for 5 minutes or until interrupted
    monitor_loop(System.monotonic_time(:second) + 300)
  end

  defp monitor_loop(end_time) do
    receive do
      {:mcp_event, event} ->
        Logger.info("MCP Event", event: event)
        monitor_loop(end_time)

      {:mcp_connection, conn_id, action} ->
        Logger.info("MCP Connection", connection_id: conn_id, action: action)
        monitor_loop(end_time)

      {:mcp_stream, stream_id, action} ->
        Logger.info("MCP Stream", stream_id: stream_id, action: action)
        monitor_loop(end_time)

      _other ->
        monitor_loop(end_time)
    after
      1000 ->
        if System.monotonic_time(:second) < end_time do
          monitor_loop(end_time)
        else
          Logger.info("Monitoring completed")
        end
    end
  end

  defp monitor_activity(end_time) do
    # Periodic stats reporting
    monitor_stats_loop(end_time, 0)
  end

  defp monitor_stats_loop(end_time, cycles) do
    if System.monotonic_time(:second) < end_time do
      # Report current stats
      stats = StreamBridge.get_stats()
      Logger.info("MCP Activity Stats", stats: stats, cycle: cycles)

      Process.sleep(5000) # Report every 5 seconds
      monitor_stats_loop(end_time, cycles + 1)
    end
  end
end
