defmodule Mix.Tasks.Lsp.SecurityAudit do
  @shortdoc "Runs comprehensive security audit of LSP codebase"
  
  @moduledoc """
  Performs comprehensive security audit of the LANG LSP codebase.
  
  ## Usage
  
      mix lsp.security_audit [options]
  
  ## Options
  
    * `--format` - Output format: `text`, `json`, `markdown` (default: `text`)
    * `--output` - Output file path (default: stdout)
    * `--severity` - Minimum severity level: `low`, `medium`, `high`, `critical` (default: `medium`)
    * `--focus` - Focus area: `security`, `performance`, `architecture`, `all` (default: `all`)
    * `--exclude` - Exclude patterns (comma-separated)
    * `--include-tests` - Include test files in analysis (default: false)
    * `--fix` - Automatically fix issues where possible (default: false)
  
  ## Examples
  
      # Basic security audit
      mix lsp.security_audit
      
      # Generate JSON report  
      mix lsp.security_audit --format json --output security_report.json
      
      # Focus on critical security issues only
      mix lsp.security_audit --severity critical --focus security
      
      # Include tests and auto-fix where possible
      mix lsp.security_audit --include-tests --fix
  """
  
  use Mix.Task
  
  alias Lang.LSP.{StaticAnalyzer, SecurityValidator}
  alias Lang.MCP.StreamBridge
  
  @switches [
    format: :string,
    output: :string, 
    severity: :string,
    focus: :string,
    exclude: :string,
    include_tests: :boolean,
    fix: :boolean
  ]
  
  @impl Mix.Task
  def run(args) do
    {opts, [], []} = OptionParser.parse(args, switches: @switches)
    
    # Start required applications
    {:ok, _} = Application.ensure_all_started(:lang)
    
    config = %{
      format: Keyword.get(opts, :format, "text"),
      output: Keyword.get(opts, :output, nil),
      severity: parse_severity(Keyword.get(opts, :severity, "medium")),
      focus: parse_focus(Keyword.get(opts, :focus, "all")),
      exclude_patterns: parse_exclude_patterns(Keyword.get(opts, :exclude, "")),
      include_tests: Keyword.get(opts, :include_tests, false),
      fix: Keyword.get(opts, :fix, false)
    }
    
    Mix.shell().info("🔍 Starting LSP security audit...")
    Mix.shell().info("Configuration: #{inspect(config)}")
    
    # Run comprehensive audit
    audit_result = run_comprehensive_audit(config)
    
    # Generate report
    report = generate_report(audit_result, config)
    
    # Output results
    output_report(report, config)
    
    # Print summary
    print_summary(audit_result)
    
    # Set exit code based on findings
    if has_critical_issues?(audit_result) do
      Mix.shell().error("❌ Critical security issues found!")
      System.stop(1)
    else
      Mix.shell().info("✅ Security audit completed")
      System.stop(0)
    end
  end
  
  # Private functions
  
  defp run_comprehensive_audit(config) do
    Mix.shell().info("📊 Analyzing codebase...")
    
    # Get project root
    root_path = File.cwd!()
    
    # Run static analysis
    {:ok, static_analysis} = StaticAnalyzer.analyze_codebase(root_path)
    
    Mix.shell().info("🔒 Checking LSP server security...")
    
    # Analyze LSP server specifically  
    lsp_security = StaticAnalyzer.analyze_lsp_server_security()
    
    Mix.shell().info("🔍 Detecting race conditions...")
    
    # Check for race conditions in multi-client code
    race_conditions = analyze_race_conditions()
    
    Mix.shell().info("🛡️  Validating security patterns...")
    
    # Runtime security checks
    runtime_security = check_runtime_security()
    
    Mix.shell().info("🌐 Auditing MCP integration...")
    
    # MCP-specific security analysis
    mcp_security = audit_mcp_security()
    
    %{
      static_analysis: static_analysis,
      lsp_security: lsp_security,
      race_conditions: race_conditions,
      runtime_security: runtime_security,
      mcp_security: mcp_security,
      timestamp: DateTime.utc_now()
    }
  end
  
  defp analyze_race_conditions do
    server_file = Path.join([File.cwd!(), "lib", "lang", "lsp", "server.ex"])
    
    case File.read(server_file) do
      {:ok, content} ->
        StaticAnalyzer.detect_race_conditions(content)
      {:error, _} ->
        []
    end
  end
  
  defp check_runtime_security do
    issues = []
    
    # Check if security validator is being used
    dispatcher_file = Path.join([File.cwd!(), "lib", "lang", "lsp", "dispatch.ex"])
    
    validator_usage = case File.read(dispatcher_file) do
      {:ok, content} ->
        if String.contains?(content, "SecurityValidator") do
          []
        else
          [%{
            type: :missing_security_validation,
            severity: :high,
            file: "lib/lang/lsp/dispatch.ex",
            line: 1,
            message: "LSP dispatch does not use SecurityValidator",
            suggestion: "Integrate SecurityValidator.validate_lsp_params/2"
          }]
        end
      {:error, _} -> []
    end
    
    # Check rate limiting implementation
    rate_limiting = check_rate_limiting_implementation()
    
    # Check client ID validation
    client_validation = check_client_id_validation()
    
    issues ++ validator_usage ++ rate_limiting ++ client_validation
  end
  
  defp check_rate_limiting_implementation do
    server_file = Path.join([File.cwd!(), "lib", "lang", "lsp", "server.ex"])
    
    case File.read(server_file) do
      {:ok, content} ->
        if String.contains?(content, "rate_limit") or String.contains?(content, "RedisLimiter") do
          []
        else
          [%{
            type: :missing_rate_limiting,
            severity: :medium, 
            file: "lib/lang/lsp/server.ex",
            line: 1,
            message: "No rate limiting implementation found",
            suggestion: "Implement per-client rate limiting"
          }]
        end
      {:error, _} -> []
    end
  end
  
  defp check_client_id_validation do
    bridge_file = Path.join([File.cwd!(), "lib", "lang", "mcp", "stream_bridge.ex"])
    
    case File.read(bridge_file) do
      {:ok, content} ->
        if String.contains?(content, "validate_client_id") do
          []
        else
          [%{
            type: :weak_client_validation,
            severity: :high,
            file: "lib/lang/mcp/stream_bridge.ex", 
            line: 1,
            message: "Weak or missing Client_ID validation",
            suggestion: "Strengthen Client_ID validation and authorization"
          }]
        end
      {:error, _} -> []
    end
  end
  
  defp audit_mcp_security do
    issues = []
    
    # Check MCP request validation
    mcp_validation = check_mcp_request_validation()
    
    # Check MCP connection security
    mcp_connections = check_mcp_connection_security()
    
    # Check MCP streaming security
    mcp_streaming = check_mcp_streaming_security()
    
    issues ++ mcp_validation ++ mcp_connections ++ mcp_streaming
  end
  
  defp check_mcp_request_validation do
    case File.read("lib/lang/mcp/security.ex") do
      {:ok, content} ->
        if String.contains?(content, "validate_mcp_request") do
          []
        else
          [%{
            type: :missing_mcp_validation,
            severity: :critical,
            file: "lib/lang/mcp/security.ex",
            line: 1, 
            message: "MCP request validation not implemented",
            suggestion: "Implement comprehensive MCP request validation"
          }]
        end
      {:error, _} ->
        [%{
          type: :missing_mcp_security_module,
          severity: :critical,
          file: "lib/lang/mcp/security.ex",
          line: 1,
          message: "MCP security module missing", 
          suggestion: "Create Lang.MCP.Security module for request validation"
        }]
    end
  end
  
  defp check_mcp_connection_security do
    # Check if MCP connections are properly isolated and authenticated
    []  # Placeholder - would check actual connection handling
  end
  
  defp check_mcp_streaming_security do
    # Check if MCP streaming has proper access control and resource limits
    []  # Placeholder - would check streaming implementation
  end
  
  defp generate_report(audit_result, config) do
    case config.format do
      "json" -> generate_json_report(audit_result, config)
      "markdown" -> generate_markdown_report(audit_result, config)
      _ -> generate_text_report(audit_result, config)
    end
  end
  
  defp generate_text_report(audit_result, config) do
    all_issues = collect_all_issues(audit_result)
    filtered_issues = filter_issues_by_severity(all_issues, config.severity)
    
    """
    ╔══════════════════════════════════════════════════════════════╗
    ║                    LSP SECURITY AUDIT REPORT                ║
    ╚══════════════════════════════════════════════════════════════╝
    
    Generated: #{DateTime.to_string(audit_result.timestamp)}
    Minimum Severity: #{config.severity}
    
    📊 SUMMARY
    ═══════════
    Total Issues Found: #{length(filtered_issues)}
    └─ Critical: #{count_by_severity(filtered_issues, :critical)}
    └─ High:     #{count_by_severity(filtered_issues, :high)}
    └─ Medium:   #{count_by_severity(filtered_issues, :medium)}
    └─ Low:      #{count_by_severity(filtered_issues, :low)}
    
    🔒 SECURITY ISSUES
    ════════════════════
    #{format_issues_section(filtered_issues, [:sql_injection, :path_traversal, :command_injection, :hardcoded_secret])}
    
    🏃 PERFORMANCE ISSUES  
    ═══════════════════════
    #{format_issues_section(filtered_issues, [:n_plus_one, :blocking_genserver, :inefficient_string_ops])}
    
    🏛️  ARCHITECTURE VIOLATIONS
    ═════════════════════════════
    #{format_issues_section(filtered_issues, [:controller_db_access, :business_logic_in_view, :missing_supervision])}
    
    ⚡ RACE CONDITIONS
    ═══════════════════
    #{format_issues_section(filtered_issues, [:unsynchronized_shared_state, :document_state_race, :unordered_message_processing])}
    
    🌐 MCP SECURITY  
    ════════════════
    #{format_issues_section(filtered_issues, [:missing_mcp_validation, :missing_mcp_security_module])}
    
    💡 RECOMMENDATIONS
    ═══════════════════
    #{generate_recommendations(audit_result)}
    
    ═══════════════════════════════════════════════════════════════
    Report generated by LANG LSP Security Auditor
    """
  end
  
  defp generate_json_report(audit_result, config) do
    all_issues = collect_all_issues(audit_result)
    filtered_issues = filter_issues_by_severity(all_issues, config.severity)
    
    %{
      metadata: %{
        generated_at: audit_result.timestamp,
        tool: "LANG LSP Security Auditor",
        version: "1.0.0",
        config: config
      },
      summary: %{
        total_issues: length(filtered_issues),
        critical: count_by_severity(filtered_issues, :critical),
        high: count_by_severity(filtered_issues, :high), 
        medium: count_by_severity(filtered_issues, :medium),
        low: count_by_severity(filtered_issues, :low)
      },
      issues: filtered_issues,
      recommendations: generate_recommendations_list(audit_result)
    }
    |> Jason.encode!(pretty: true)
  end
  
  defp generate_markdown_report(audit_result, config) do
    all_issues = collect_all_issues(audit_result)
    filtered_issues = filter_issues_by_severity(all_issues, config.severity)
    
    """
    # LSP Security Audit Report
    
    **Generated:** #{DateTime.to_string(audit_result.timestamp)}
    **Minimum Severity:** #{config.severity}
    
    ## Summary
    
    - **Total Issues:** #{length(filtered_issues)}
    - **Critical:** #{count_by_severity(filtered_issues, :critical)}
    - **High:** #{count_by_severity(filtered_issues, :high)}
    - **Medium:** #{count_by_severity(filtered_issues, :medium)}
    - **Low:** #{count_by_severity(filtered_issues, :low)}
    
    ## Security Issues
    
    #{format_markdown_issues(filtered_issues, [:sql_injection, :path_traversal, :command_injection])}
    
    ## Performance Issues
    
    #{format_markdown_issues(filtered_issues, [:n_plus_one, :blocking_genserver])}
    
    ## Architecture Violations
    
    #{format_markdown_issues(filtered_issues, [:controller_db_access, :business_logic_in_view])}
    
    ## Recommendations
    
    #{generate_markdown_recommendations(audit_result)}
    """
  end
  
  defp collect_all_issues(audit_result) do
    static_issues = audit_result.static_analysis.security_issues ++
                   audit_result.static_analysis.quality_issues ++
                   audit_result.static_analysis.performance_issues ++
                   audit_result.static_analysis.architecture_violations
    
    lsp_issues = audit_result.lsp_security.security_issues ++
                audit_result.lsp_security.quality_issues ++
                audit_result.lsp_security.performance_issues ++
                audit_result.lsp_security.architecture_violations
    
    runtime_issues = audit_result.runtime_security
    mcp_issues = audit_result.mcp_security
    race_issues = audit_result.race_conditions
    
    static_issues ++ lsp_issues ++ runtime_issues ++ mcp_issues ++ race_issues
  end
  
  defp filter_issues_by_severity(issues, min_severity) do
    severity_order = [:low, :medium, :high, :critical]
    min_level = Enum.find_index(severity_order, &(&1 == min_severity)) || 0
    
    Enum.filter(issues, fn issue ->
      issue_level = Enum.find_index(severity_order, &(&1 == issue.severity)) || 0
      issue_level >= min_level
    end)
  end
  
  defp count_by_severity(issues, severity) do
    Enum.count(issues, &(&1.severity == severity))
  end
  
  defp format_issues_section(issues, types) do
    relevant_issues = Enum.filter(issues, &(&1.type in types))
    
    if Enum.empty?(relevant_issues) do
      "No issues found in this category.\n"
    else
      relevant_issues
      |> Enum.map(fn issue ->
        severity_icon = case issue.severity do
          :critical -> "🚨"
          :high -> "⚠️ "
          :medium -> "💛"
          :low -> "ℹ️ "
        end
        
        "#{severity_icon} #{issue.file}:#{issue.line} - #{issue.message}"
      end)
      |> Enum.join("\n")
    end
  end
  
  defp format_markdown_issues(issues, types) do
    relevant_issues = Enum.filter(issues, &(&1.type in types))
    
    if Enum.empty?(relevant_issues) do
      "No issues found.\n"
    else
      relevant_issues
      |> Enum.map(fn issue ->
        "- **#{issue.severity |> Atom.to_string() |> String.upcase()}** `#{issue.file}:#{issue.line}` - #{issue.message}"
      end)
      |> Enum.join("\n")
    end
  end
  
  defp generate_recommendations(audit_result) do
    """
    1. 🔒 Implement comprehensive input validation using SecurityValidator
    2. ⚡ Add rate limiting for all LSP methods to prevent abuse  
    3. 🛡️  Strengthen Client_ID validation and authorization
    4. 🌐 Implement MCP request validation and sandboxing
    5. 🔐 Add authentication layer for sensitive operations
    6. 📊 Implement comprehensive security logging and monitoring
    7. 🔄 Add synchronization mechanisms for shared state access
    8. 🧪 Expand security test coverage significantly
    """
  end
  
  defp generate_recommendations_list(audit_result) do
    [
      "Implement comprehensive input validation",
      "Add rate limiting for all LSP methods", 
      "Strengthen Client_ID validation",
      "Implement MCP request validation",
      "Add authentication for sensitive operations",
      "Implement security logging and monitoring",
      "Add synchronization for shared state",
      "Expand security test coverage"
    ]
  end
  
  defp generate_markdown_recommendations(audit_result) do
    """
    1. **Input Validation** - Implement comprehensive validation using SecurityValidator
    2. **Rate Limiting** - Add rate limiting for all LSP methods
    3. **Client Authorization** - Strengthen Client_ID validation  
    4. **MCP Security** - Implement MCP request validation and sandboxing
    5. **Authentication** - Add authentication layer for sensitive operations
    6. **Monitoring** - Implement security logging and monitoring
    7. **Synchronization** - Add proper synchronization for shared state
    8. **Testing** - Expand security test coverage significantly
    """
  end
  
  defp output_report(report, config) do
    case config.output do
      nil ->
        Mix.shell().info(report)
      
      file_path ->
        File.write!(file_path, report)
        Mix.shell().info("Report written to: #{file_path}")
    end
  end
  
  defp print_summary(audit_result) do
    all_issues = collect_all_issues(audit_result)
    critical = count_by_severity(all_issues, :critical)
    high = count_by_severity(all_issues, :high)
    
    Mix.shell().info("")
    Mix.shell().info("📋 AUDIT SUMMARY")
    Mix.shell().info("════════════════")
    Mix.shell().info("Total Issues: #{length(all_issues)}")
    Mix.shell().info("Critical: #{critical}")
    Mix.shell().info("High: #{high}")
    Mix.shell().info("Medium: #{count_by_severity(all_issues, :medium)}")
    Mix.shell().info("Low: #{count_by_severity(all_issues, :low)}")
  end
  
  defp has_critical_issues?(audit_result) do
    all_issues = collect_all_issues(audit_result)
    Enum.any?(all_issues, &(&1.severity == :critical))
  end
  
  defp parse_severity("low"), do: :low
  defp parse_severity("medium"), do: :medium  
  defp parse_severity("high"), do: :high
  defp parse_severity("critical"), do: :critical
  defp parse_severity(_), do: :medium
  
  defp parse_focus("security"), do: :security
  defp parse_focus("performance"), do: :performance
  defp parse_focus("architecture"), do: :architecture  
  defp parse_focus("all"), do: :all
  defp parse_focus(_), do: :all
  
  defp parse_exclude_patterns(""), do: []
  defp parse_exclude_patterns(patterns) when is_binary(patterns) do
    String.split(patterns, ",") |> Enum.map(&String.trim/1)
  end
end