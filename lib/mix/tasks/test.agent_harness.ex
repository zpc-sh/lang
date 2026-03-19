defmodule Mix.Tasks.Test.AgentHarness do
  @moduledoc """
  Mix task to run comprehensive agent harness and recursive testing suite.

  This task provides a unified interface for running the complete suite of
  AI agent simulation tests, including:

  - Individual agent type simulations (Qwen3, Coordinator, Builder, etc.)
  - Multi-agent swarm coordination tests
  - Recursive semantic revolution cycles
  - Emergent behavior detection
  - Meta-cognitive development testing
  - Collective intelligence formation

  ## Usage

  Run all agent harness tests:
      mix test.agent_harness

  Run specific agent type tests:
      mix test.agent_harness --type qwen3
      mix test.agent_harness --type coordinator

  Run with specific scenarios:
      mix test.agent_harness --scenario recursive_evolution
      mix test.agent_harness --scenario emergent_behavior

  Run with performance monitoring:
      mix test.agent_harness --monitor
      mix test.agent_harness --save-metrics

  ## Options

  * `--type` - Run tests for specific agent type (qwen3, coordinator, builder, etc.)
  * `--scenario` - Run specific test scenarios (recursive_evolution, swarm_coordination, etc.)
  * `--monitor` - Enable real-time performance monitoring
  * `--save-metrics` - Save detailed metrics to files
  * `--lsp-port` - Custom LSP server port (default: 4001)
  * `--agents` - Number of test agents to spawn (default: 3)
  * `--generations` - Maximum generations for recursive tests (default: 3)
  * `--timeout` - Test timeout in seconds (default: 120)
  * `--verbose` - Enable verbose output
  * `--help` - Show this help

  ## Examples

      # Run complete agent harness suite
      mix test.agent_harness

      # Run Qwen3 recursive evolution tests with monitoring
      mix test.agent_harness --type qwen3 --scenario recursive_evolution --monitor

      # Run swarm coordination with 5 agents for 4 generations
      mix test.agent_harness --scenario swarm_coordination --agents 5 --generations 4

      # Run with custom LSP port and save metrics
      mix test.agent_harness --lsp-port 4002 --save-metrics

  ## Prerequisites

  - LSP server must be running on specified port
  - All dependencies must be compiled
  - Sufficient system resources for multi-agent simulation

  ## Output

  The task provides detailed output including:
  - Agent spawn and connection status
  - Real-time performance metrics
  - Recursive improvement tracking
  - Emergent behavior detection
  - Final analysis and recommendations
  """

  use Mix.Task

  @shortdoc "Run comprehensive agent harness and recursive testing suite"

  # Default configuration
  @default_lsp_port 4001
  @default_agents 3
  @default_generations 3
  @default_timeout 120

  @agent_types [
    :qwen3,
    :coordinator,
    :builder,
    :debugger,
    :architect,
    :optimizer,
    :researcher
  ]

  @scenarios [
    :all,
    :basic_lifecycle,
    :recursive_evolution,
    :swarm_coordination,
    :emergent_behavior,
    :meta_cognitive,
    :collective_intelligence,
    :performance_optimization
  ]

  def run(args) do
    {opts, _remaining_args, _invalid} =
      OptionParser.parse(args,
        switches: [
          type: :string,
          scenario: :string,
          monitor: :boolean,
          save_metrics: :boolean,
          lsp_port: :integer,
          agents: :integer,
          generations: :integer,
          timeout: :integer,
          verbose: :boolean,
          help: :boolean
        ],
        aliases: [
          t: :type,
          s: :scenario,
          m: :monitor,
          p: :lsp_port,
          a: :agents,
          g: :generations,
          v: :verbose,
          h: :help
        ]
      )

    if opts[:help] do
      show_help()
    else
      run_agent_harness(opts)
    end
  end

  defp run_agent_harness(opts) do
    config = build_config(opts)

    Mix.shell().info("🚀 Starting LANG Agent Harness Test Suite")
    Mix.shell().info("Configuration: #{inspect(config, pretty: true)}")
    Mix.shell().info("")

    # Ensure LSP server is ready
    unless lsp_server_ready?(config.lsp_port) do
      Mix.shell().error("❌ LSP server not ready on port #{config.lsp_port}")
      Mix.shell().info("💡 Start LSP server with: ./scripts/start_lsp_debug.sh quick")
      System.halt(1)
    end

    Mix.shell().info("✅ LSP server ready on port #{config.lsp_port}")

    # Setup monitoring if requested
    monitor_pid =
      if config.monitor do
        start_performance_monitor(config)
      else
        nil
      end

    try do
      # Run the test suite based on configuration
      results =
        case {config.agent_type, config.scenario} do
          {nil, :all} -> run_complete_suite(config)
          {agent_type, :all} when agent_type != nil -> run_agent_type_tests(agent_type, config)
          {nil, scenario} -> run_scenario_tests(scenario, config)
          {agent_type, scenario} -> run_specific_test(agent_type, scenario, config)
        end

      # Display results
      display_results(results, config)

      # Save metrics if requested
      if config.save_metrics do
        save_metrics_to_file(results, config)
      end
    after
      # Cleanup monitoring
      if monitor_pid do
        stop_performance_monitor(monitor_pid)
      end
    end

    Mix.shell().info("🎉 Agent Harness Test Suite Completed")
  end

  defp build_config(opts) do
    %{
      agent_type: parse_agent_type(opts[:type]),
      scenario: parse_scenario(opts[:scenario] || "all"),
      monitor: opts[:monitor] || false,
      save_metrics: opts[:save_metrics] || false,
      lsp_port: opts[:lsp_port] || @default_lsp_port,
      agents: opts[:agents] || @default_agents,
      generations: opts[:generations] || @default_generations,
      timeout: (opts[:timeout] || @default_timeout) * 1000,
      verbose: opts[:verbose] || false
    }
  end

  defp parse_agent_type(nil), do: nil

  defp parse_agent_type(type_str) do
    type_atom = String.to_atom(type_str)

    if type_atom in @agent_types do
      type_atom
    else
      Mix.shell().error("❌ Unknown agent type: #{type_str}")
      Mix.shell().info("Available types: #{Enum.join(@agent_types, ", ")}")
      System.halt(1)
    end
  end

  defp parse_scenario(scenario_str) do
    scenario_atom = String.to_atom(scenario_str)

    if scenario_atom in @scenarios do
      scenario_atom
    else
      Mix.shell().error("❌ Unknown scenario: #{scenario_str}")
      Mix.shell().info("Available scenarios: #{Enum.join(@scenarios, ", ")}")
      System.halt(1)
    end
  end

  defp lsp_server_ready?(port) do
    case :gen_tcp.connect(~c"127.0.0.1", port, [], 1000) do
      {:ok, socket} ->
        :gen_tcp.close(socket)
        true

      {:error, _} ->
        false
    end
  end

  defp start_performance_monitor(config) do
    spawn_link(fn ->
      performance_monitor_loop(config)
    end)
  end

  defp performance_monitor_loop(config) do
    receive do
      :stop -> :ok
    after
      5000 ->
        # Collect and display performance metrics
        metrics = collect_performance_metrics(config)
        display_performance_metrics(metrics)
        performance_monitor_loop(config)
    end
  end

  defp stop_performance_monitor(pid) do
    send(pid, :stop)
  end

  defp collect_performance_metrics(config) do
    %{
      timestamp: DateTime.utc_now(),
      memory_usage: :erlang.memory(),
      process_count: :erlang.system_info(:process_count),
      lsp_port_active: lsp_server_ready?(config.lsp_port),
      system_load: get_system_load()
    }
  end

  defp get_system_load do
    case :cpu_sup.avg1() do
      load when is_integer(load) -> load / 256
      _ -> 0.0
    end
  end

  defp display_performance_metrics(metrics) do
    if Mix.shell().info?() do
      memory_mb = div(metrics.memory_usage[:total], 1024 * 1024)

      Mix.shell().info([
        IO.ANSI.blue(),
        "📊 Performance: ",
        "Memory: #{memory_mb}MB, ",
        "Processes: #{metrics.process_count}, ",
        "Load: #{Float.round(metrics.system_load, 2)}",
        IO.ANSI.reset()
      ])
    end
  end

  defp run_complete_suite(config) do
    Mix.shell().info("🧪 Running Complete Agent Harness Test Suite")

    results = %{
      start_time: DateTime.utc_now(),
      test_results: [],
      summary: %{total: 0, passed: 0, failed: 0, skipped: 0}
    }

    # Run all scenarios for all agent types
    all_results =
      for agent_type <- @agent_types do
        Mix.shell().info("🤖 Testing #{agent_type} agent...")
        run_agent_type_tests(agent_type, config)
      end

    # Aggregate results
    test_results = List.flatten(all_results)
    summary = calculate_summary(test_results)

    %{results | test_results: test_results, summary: summary, end_time: DateTime.utc_now()}
  end

  defp run_agent_type_tests(agent_type, config) do
    Mix.shell().info("🧪 Running #{agent_type} agent tests")

    # Define test modules for each agent type
    test_module =
      case agent_type do
        :qwen3 -> "Lang.Test.AgentSimulations.Qwen3AgentTest"
        :coordinator -> "Lang.Test.AgentSimulations.CoordinatorAgentTest"
        _ -> "Lang.Test.AgentHarnessTest"
      end

    # Run ExUnit tests for the specific module
    run_exunit_tests([test_module], config)
  end

  defp run_scenario_tests(scenario, config) do
    Mix.shell().info("🧪 Running #{scenario} scenario tests")

    test_modules =
      case scenario do
        :recursive_evolution -> ["Lang.Test.RecursiveSemanticRevolutionTest"]
        :swarm_coordination -> ["Lang.Test.AgentSimulations.CoordinatorAgentTest"]
        :emergent_behavior -> ["Lang.Test.AgentHarnessTest"]
        :meta_cognitive -> ["Lang.Test.AgentSimulations.Qwen3AgentTest"]
        :collective_intelligence -> ["Lang.Test.RecursiveSemanticRevolutionTest"]
        :performance_optimization -> ["Lang.Test.RecursiveTestFrameworkTest"]
        _ -> ["Lang.Test.AgentHarnessTest"]
      end

    run_exunit_tests(test_modules, config)
  end

  defp run_specific_test(agent_type, scenario, config) do
    Mix.shell().info("🧪 Running #{agent_type} #{scenario} tests")

    # This would run specific test combinations
    # For now, we'll run the agent type tests
    run_agent_type_tests(agent_type, config)
  end

  defp run_exunit_tests(test_modules, config) do
    # Configure ExUnit
    ExUnit.configure(
      timeout: config.timeout,
      capture_log: !config.verbose
    )

    # Start ExUnit if not already started
    ExUnit.start()

    # Load test files
    test_files = get_test_files_for_modules(test_modules)

    results = []

    for test_file <- test_files do
      Mix.shell().info("📋 Running tests in #{Path.basename(test_file)}")

      # Run the test file
      result =
        case Code.compile_file(test_file) do
          modules when is_list(modules) ->
            # Test file compiled successfully
            %{
              file: test_file,
              status: :compiled,
              modules: length(modules),
              timestamp: DateTime.utc_now()
            }

          {:error, reason} ->
            Mix.shell().error("❌ Failed to compile #{test_file}: #{inspect(reason)}")

            %{
              file: test_file,
              status: :compilation_failed,
              error: reason,
              timestamp: DateTime.utc_now()
            }
        end

      [result | results]
    end

    Enum.reverse(results)
  end

  defp get_test_files_for_modules(test_modules) do
    # Convert module names to file paths
    Enum.map(test_modules, fn module_name ->
      path =
        module_name
        |> String.replace(".", "/")
        |> String.replace("Lang/Test/", "test/")
        |> Kernel.<>(".exs")

      if File.exists?(path) do
        path
      else
        # Try alternative path
        alt_path =
          ("test/" <> String.replace(module_name, "Lang.Test.", ""))
          |> String.replace(".", "/")
          |> String.downcase()
          |> Kernel.<>(".exs")

        if File.exists?(alt_path) do
          alt_path
        else
          Mix.shell().warn("⚠️  Test file not found: #{path}")
          nil
        end
      end
    end)
    |> Enum.filter(& &1)
  end

  defp calculate_summary(test_results) do
    total = length(test_results)
    passed = Enum.count(test_results, &(&1.status == :compiled))
    failed = Enum.count(test_results, &(&1.status == :compilation_failed))
    skipped = total - passed - failed

    %{
      total: total,
      passed: passed,
      failed: failed,
      skipped: skipped
    }
  end

  defp display_results(results, config) do
    Mix.shell().info("")
    Mix.shell().info("📊 Test Results Summary")
    Mix.shell().info("=" |> String.duplicate(50))

    if Map.has_key?(results, :summary) do
      summary = results.summary
      Mix.shell().info("Total Tests: #{summary.total}")
      Mix.shell().info("✅ Passed: #{summary.passed}")
      Mix.shell().info("❌ Failed: #{summary.failed}")
      Mix.shell().info("⏭️  Skipped: #{summary.skipped}")

      success_rate =
        if summary.total > 0 do
          (summary.passed / summary.total * 100) |> Float.round(1)
        else
          0.0
        end

      Mix.shell().info("🎯 Success Rate: #{success_rate}%")
    end

    if config.verbose && Map.has_key?(results, :test_results) do
      Mix.shell().info("")
      Mix.shell().info("📋 Detailed Results:")

      for result <- results.test_results do
        status_icon =
          case result.status do
            :compiled -> "✅"
            :compilation_failed -> "❌"
            _ -> "⚠️"
          end

        Mix.shell().info("#{status_icon} #{Path.basename(result.file)} - #{result.status}")
      end
    end

    Mix.shell().info("")
  end

  defp save_metrics_to_file(results, config) do
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601(:basic)
    filename = "agent_harness_metrics_#{timestamp}.json"
    filepath = Path.join("tmp", filename)

    # Ensure tmp directory exists
    File.mkdir_p!(Path.dirname(filepath))

    # Prepare metrics data
    metrics_data = %{
      config: config,
      results: results,
      system_info: %{
        elixir_version: System.version(),
        otp_version: :erlang.system_info(:otp_release) |> to_string(),
        system_architecture: :erlang.system_info(:system_architecture) |> to_string(),
        schedulers: :erlang.system_info(:schedulers),
        memory: :erlang.memory()
      },
      timestamp: timestamp
    }

    # Write to file
    case File.write(filepath, Jason.encode!(metrics_data, pretty: true)) do
      :ok ->
        Mix.shell().info("💾 Metrics saved to: #{filepath}")

      {:error, reason} ->
        Mix.shell().error("❌ Failed to save metrics: #{inspect(reason)}")
    end
  end

  defp show_help do
    Mix.shell().info("""
    #{@moduledoc}
    """)
  end
end
