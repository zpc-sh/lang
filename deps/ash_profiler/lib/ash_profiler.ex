defmodule AshProfiler do
  @moduledoc """
  Performance profiling and optimization toolkit for Ash Framework applications.
  
  AshProfiler acts as a performance optimization agent that automatically analyzes your 
  Ash codebase to identify bottlenecks, score DSL complexity, and provide actionable 
  optimization recommendations.
  
  ## Features
  
  - **DSL Complexity Analysis** - Scores resource complexity and identifies optimization opportunities
  - **Compilation Profiling** - Tracks compilation performance bottlenecks  
  - **Container Detection** - Specialized analysis for containerized environments
  - **Multiple Output Formats** - Console, JSON, and HTML reporting
  - **Optimization Recommendations** - AI-like suggestions for performance improvements
  
  ## Quick Start
  
      # Analyze all domains with default settings
      AshProfiler.analyze()
      
      # Generate comprehensive HTML report
      AshProfiler.analyze(output: :html, file: "ash_performance_report.html")
      
      # Focus on specific high-impact domains
      AshProfiler.analyze(
        domains: [MyApp.CoreDomain, MyApp.UserDomain],
        threshold: 50,
        include_optimizations: true
      )
  
  ## Command Line Usage
  
      # Basic profiling
      mix ash_profiler
      
      # Detailed analysis with custom threshold
      mix ash_profiler --output html --file report.html --threshold 80
      
      # Container-optimized analysis
      mix ash_profiler --container-mode --threshold 50
  
  ## Options
  
    * `:domains` - List of domains to analyze (default: auto-discover)
    * `:output` - Output format `:console`, `:json`, `:html` (default: `:console`)
    * `:file` - Output file path for JSON/HTML reports
    * `:threshold` - Complexity threshold for warnings (default: 100)
    * `:container_mode` - Enable container-specific analysis (default: auto-detect)
    * `:include_optimizations` - Include optimization suggestions (default: true)
    
  ## Performance Scoring
  
  Resources are scored based on DSL complexity:
  
  - **Low (< 50)**: Well-optimized resource
  - **Medium (50-100)**: Moderate complexity  
  - **High (100-150)**: Review recommended
  - **Critical (> 150)**: Optimization needed
  
  ## Integration Examples
  
      # CI/CD Integration - fail build if complexity exceeds threshold
      AshProfiler.analyze(output: :json, file: "metrics.json")
      |> case do
        %{summary: %{total_complexity: complexity}} when complexity > 1000 ->
          System.halt(1)
        _ -> :ok
      end
      
      # Weekly performance audit
      AshProfiler.analyze(
        output: :html,
        file: "weekly_performance_\#{Date.utc_today()}.html",
        include_optimizations: true
      )
  """

  alias AshProfiler.{
    DomainAnalyzer,
    ContainerDetector
  }

  @doc """
  Runs comprehensive performance analysis of Ash resources.
  
  ## Examples
  
      # Basic analysis
      AshProfiler.analyze()
      
      # Custom options
      AshProfiler.analyze(
        domains: [MyApp.CoreDomain],
        output: :html,
        file: "ash_profile.html",
        threshold: 50
      )
  """
  def analyze(opts \\ []) do
    opts = normalize_options(opts)
    
    domains = opts[:domains] || discover_domains()
    
    results = %{
      environment: analyze_environment(opts),
      domains: analyze_domains(domains, opts),
      summary: generate_summary(domains, opts)
    }
    
    generate_report(results, opts)
    results
  end

  # Private implementation functions
  defp normalize_options(opts) do
    defaults = [
      output: :console,
      threshold: 100,
      container_mode: ContainerDetector.in_container?(),
      include_optimizations: true
    ]
    
    Keyword.merge(defaults, opts)
  end

  defp discover_domains do
    # Auto-discover Ash domains from application config
    app_domains = Application.get_env(:ash, :domains, [])
    main_app = Mix.Project.config()[:app]
    app_specific_domains = Application.get_env(main_app, :ash_domains, [])
    
    (app_domains ++ app_specific_domains) |> Enum.uniq()
  end

  defp analyze_environment(opts) do
    if opts[:container_mode] do
      ContainerDetector.analyze_container_environment()
    else
      %{is_container: false, system_resources: %{}, performance_characteristics: %{}}
    end
  end

  defp analyze_domains(domains, opts) do
    Enum.map(domains, &DomainAnalyzer.analyze_domain(&1, opts))
  end

  defp generate_summary(domains, _opts) do
    total_resources = Enum.sum(Enum.map(domains, &length(&1)))
    %{
      total_domains: length(domains),
      total_resources: total_resources
    }
  end

  defp generate_report(results, opts) do
    case opts[:output] do
      :console -> generate_console_report(results, opts)
      :json -> generate_json_report(results, opts)
      :html -> generate_html_report(results, opts)
    end
  end

  defp generate_console_report(results, _opts) do
    IO.puts("=== Ash Profiler Results ===")
    IO.puts("Domains analyzed: #{results.summary.total_domains}")
    IO.puts("Total resources: #{results.summary.total_resources}")
    
    if results.environment.is_container do
      IO.puts("Container environment detected")
    end
  end

  defp generate_json_report(results, opts) do
    json = Jason.encode!(results, pretty: true)
    
    if opts[:file] do
      File.write!(opts[:file], json)
      IO.puts("JSON report written to #{opts[:file]}")
    else
      IO.puts(json)
    end
  end

  defp generate_html_report(results, opts) do
    html = """
    <!DOCTYPE html>
    <html>
    <head>
      <title>Ash Profiler Report</title>
      <style>
        body { font-family: Arial, sans-serif; margin: 40px; }
        .summary { background: #f5f5f5; padding: 20px; border-radius: 5px; }
        .metric { margin: 10px 0; }
      </style>
    </head>
    <body>
      <h1>Ash Profiler Report</h1>
      <div class="summary">
        <div class="metric">Domains: #{results.summary.total_domains}</div>
        <div class="metric">Resources: #{results.summary.total_resources}</div>
      </div>
    </body>
    </html>
    """
    
    if opts[:file] do
      File.write!(opts[:file], html)
      IO.puts("HTML report written to #{opts[:file]}")
    else
      IO.puts(html)
    end
  end
end
