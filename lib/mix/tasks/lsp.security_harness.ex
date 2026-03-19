defmodule Mix.Tasks.Lsp.SecurityHarness do
  @moduledoc """
  Run security harness tests for LSP and MCP components.
  
  ## Usage
  
      mix lsp.security_harness [options]
      
  ## Options
  
    * `--scenarios` - Comma-separated list of scenarios to run
    * `--clients` - Number of concurrent clients to simulate (default: 5)
    * `--duration` - Test duration in seconds (default: 30)
    * `--format` - Output format: text, json, detailed (default: text)
    * `--concurrent` - Run scenarios concurrently (default: true)
    * `--output` - Output file path (optional)
  
  ## Available Scenarios
  
    * `basic_validation` - Basic input validation and sanitization
    * `rate_limiting` - Rate limiting enforcement and bypass prevention
    * `multi_client_race` - Multi-client race condition prevention
    * `injection_attacks` - SQL injection and command injection prevention
    * `session_security` - Session hijacking and fixation prevention
    * `authorization_bypass` - Authorization bypass attempt detection
    * `resource_exhaustion` - Resource exhaustion and DoS prevention
    * `timing_attacks` - Timing attack resistance validation
  
  ## Examples
  
      # Run all scenarios with default settings
      mix lsp.security_harness
      
      # Run specific scenarios
      mix lsp.security_harness --scenarios basic_validation,rate_limiting
      
      # Run with more clients for load testing
      mix lsp.security_harness --clients 20 --duration 60
      
      # Output detailed JSON report
      mix lsp.security_harness --format json --output security_report.json
  """
  
  use Mix.Task
  require Logger
  
  alias Lang.LSP.SecurityHarness
  alias Lang.Monitoring.SecurityMonitor
  alias Lang.MCP.{SessionManager, SecurityBridge}
  
  @shortdoc "Run LSP/MCP security harness tests"
  
  @switches [
    scenarios: :string,
    clients: :integer,
    duration: :integer,
    format: :string,
    concurrent: :boolean,
    output: :string,
    help: :boolean
  ]
  
  @aliases [
    s: :scenarios,
    c: :clients,
    d: :duration,
    f: :format,
    o: :output,
    h: :help
  ]
  
  def run(args) do
    {opts, [], []} = OptionParser.parse(args, switches: @switches, aliases: @aliases)
    
    if opts[:help] do
      print_help()
    else
      run_security_harness(opts)
    end
  end
  
  defp run_security_harness(opts) do
    # Ensure dependencies are started
    {:ok, _} = Application.ensure_all_started(:lang)
    
    Mix.shell().info("Starting LSP Security Harness...")
    
    # Parse and validate options
    config = parse_options(opts)
    
    Mix.shell().info("Configuration:")
    Mix.shell().info("  Scenarios: #{inspect(config.scenarios)}")
    Mix.shell().info("  Clients: #{config.client_count}")
    Mix.shell().info("  Duration: #{config.duration_ms / 1000}s")
    Mix.shell().info("  Format: #{config.report_format}")
    Mix.shell().info("  Concurrent: #{config.concurrent}")
    Mix.shell().info("")
    
    # Start required processes
    start_dependencies()
    
    # Run the harness
    case SecurityHarness.run_security_suite(Map.to_list(config)) do
      {:ok, report} ->
        output_report(report, config, opts[:output])
        
        # Exit with appropriate code
        if report.summary.failed > 0 do
          Mix.shell().error("Security harness completed with failures!")
          System.halt(1)
        else
          Mix.shell().info("Security harness completed successfully!")
        end
      
      {:error, reason} ->
        Mix.shell().error("Security harness failed: #{inspect(reason)}")
        System.halt(1)
    end
  end
  
  defp parse_options(opts) do
    scenarios = case opts[:scenarios] do
      nil -> 
        [:basic_validation, :rate_limiting, :multi_client_race, :injection_attacks,
         :session_security, :authorization_bypass, :resource_exhaustion, :timing_attacks]
      
      scenarios_str ->
        scenarios_str
        |> String.split(",")
        |> Enum.map(&String.trim/1)
        |> Enum.map(&String.to_atom/1)
    end
    
    %{
      scenarios: scenarios,
      client_count: opts[:clients] || 5,
      duration_ms: (opts[:duration] || 30) * 1000,
      concurrent: opts[:concurrent] != false,
      report_format: String.to_atom(opts[:format] || "text")
    }
  end
  
  defp start_dependencies do
    # Start security monitor if not already running
    unless Process.whereis(SecurityMonitor) do
      {:ok, _} = SecurityMonitor.start_link()
      Mix.shell().info("Started SecurityMonitor")
    end
    
    # Start session manager if not already running
    unless Process.whereis(SessionManager) do
      {:ok, _} = SessionManager.start_link()
      Mix.shell().info("Started SessionManager")
    end
    
    # Start security bridge if not already running
    unless Process.whereis(SecurityBridge) do
      {:ok, _} = SecurityBridge.start_link()
      Mix.shell().info("Started SecurityBridge")
    end
    
    # Start security harness
    unless Process.whereis(SecurityHarness) do
      {:ok, _} = SecurityHarness.start_link()
      Mix.shell().info("Started SecurityHarness")
    end
    
    # Give processes time to initialize
    Process.sleep(1000)
  end
  
  defp output_report(report, config, output_file) do
    formatted_report = case config.report_format do
      :json -> format_json_report(report)
      :detailed -> format_detailed_report(report)
      _ -> format_text_report(report)
    end
    
    case output_file do
      nil ->
        IO.puts(formatted_report)
      
      file_path ->
        case File.write(file_path, formatted_report) do
          :ok ->
            Mix.shell().info("Report written to #{file_path}")
          
          {:error, reason} ->
            Mix.shell().error("Failed to write report to #{file_path}: #{reason}")
            IO.puts(formatted_report)
        end
    end
  end
  
  defp format_text_report(report) do
    summary = report.summary
    
    """
    
    ═══════════════════════════════════════════════════════════════
                          SECURITY HARNESS REPORT
    ═══════════════════════════════════════════════════════════════
    
    Summary:
      Total Scenarios: #{summary.total_scenarios}
      Passed: #{summary.passed}
      Failed: #{summary.failed}
      Success Rate: #{Float.round(summary.success_rate, 1)}%
      Duration: #{Float.round(summary.duration_ms / 1000, 1)}s
      Timestamp: #{DateTime.to_string(report.timestamp)}
    
    """ <>
    format_scenario_results(report.scenarios) <>
    format_recommendations(report.recommendations)
  end
  
  defp format_scenario_results(scenarios) do
    "Scenario Results:\n" <>
    (scenarios
     |> Enum.map(&format_scenario_result/1)
     |> Enum.join("\n"))
  end
  
  defp format_scenario_result(scenario) do
    status_symbol = case scenario.status do
      :passed -> "✓"
      :failed -> "✗"
      _ -> "?"
    end
    
    duration = Float.round(scenario.duration_ms / 1000, 2)
    
    base_info = "  #{status_symbol} #{scenario.scenario} - #{scenario.summary} (#{duration}s)"
    
    if scenario.status == :failed and Map.has_key?(scenario, :tests) do
      failed_tests = Enum.filter(scenario.tests, &(not &1.passed))
      
      if failed_tests != [] do
        failed_details = failed_tests
          |> Enum.map(fn test -> "      • #{test.name}: #{inspect(test.details)}" end)
          |> Enum.join("\n")
        
        base_info <> "\n" <> failed_details
      else
        base_info
      end
    else
      base_info
    end
  end
  
  defp format_recommendations([]), do: ""
  defp format_recommendations(recommendations) do
    "\nSecurity Recommendations:\n" <>
    (recommendations
     |> Enum.map(fn rec -> "  • #{rec}" end)
     |> Enum.join("\n")) <>
    "\n"
  end
  
  defp format_json_report(report) do
    Jason.encode!(report, pretty: true)
  end
  
  defp format_detailed_report(report) do
    """
    # Security Harness Report
    
    **Generated:** #{DateTime.to_string(report.timestamp)}
    
    ## Summary
    
    | Metric | Value |
    |--------|-------|
    | Total Scenarios | #{report.summary.total_scenarios} |
    | Passed | #{report.summary.passed} |
    | Failed | #{report.summary.failed} |
    | Success Rate | #{Float.round(report.summary.success_rate, 1)}% |
    | Duration | #{Float.round(report.summary.duration_ms / 1000, 1)}s |
    
    ## Scenario Details
    
    """ <>
    format_detailed_scenarios(report.scenarios) <>
    format_detailed_recommendations(report.recommendations)
  end
  
  defp format_detailed_scenarios(scenarios) do
    scenarios
    |> Enum.map(&format_detailed_scenario/1)
    |> Enum.join("\n")
  end
  
  defp format_detailed_scenario(scenario) do
    status_emoji = case scenario.status do
      :passed -> "✅"
      :failed -> "❌"
      _ -> "⚠️"
    end
    
    """
    ### #{status_emoji} #{String.capitalize(to_string(scenario.scenario))}
    
    **Description:** #{scenario.description}
    **Status:** #{String.upcase(to_string(scenario.status))}
    **Duration:** #{Float.round(scenario.duration_ms / 1000, 2)}s
    **Summary:** #{scenario.summary}
    
    """ <>
    if Map.has_key?(scenario, :tests) do
      format_test_details(scenario.tests)
    else
      ""
    end
  end
  
  defp format_test_details(tests) do
    "**Test Results:**\n\n" <>
    (tests
     |> Enum.map(fn test ->
       status = if test.passed, do: "✅", else: "❌"
       details = if test.details != %{}, do: " - #{inspect(test.details)}", else: ""
       "- #{status} #{test.name}#{details}"
     end)
     |> Enum.join("\n")) <>
    "\n\n"
  end
  
  defp format_detailed_recommendations([]), do: ""
  defp format_detailed_recommendations(recommendations) do
    """
    ## Recommendations
    
    """ <>
    (recommendations
     |> Enum.map(fn rec -> "- #{rec}" end)
     |> Enum.join("\n")) <>
    "\n"
  end
  
  defp print_help do
    Mix.shell().info(@moduledoc)
  end
end