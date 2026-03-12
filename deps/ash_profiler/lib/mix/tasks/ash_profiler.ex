defmodule Mix.Tasks.AshProfiler do
  use Mix.Task

  @shortdoc "Profile Ash DSL compilation performance"
  @moduledoc """
  Profiles Ash Framework DSL compilation performance and identifies bottlenecks.
  
  ## Usage
  
      # Basic profiling
      mix ash_profiler
      
      # Generate HTML report
      mix ash_profiler --output html --file report.html
      
      # Profile specific domains
      mix ash_profiler --domains MyApp.CoreDomain,MyApp.UserDomain
      
      # Container mode analysis
      mix ash_profiler --container-mode
  
  ## Options
  
    * `--output` - Output format: console, json, html (default: console)
    * `--file` - Output file path
    * `--domains` - Comma-separated list of domains to analyze
    * `--threshold` - Complexity threshold for warnings (default: 100)
    * `--container-mode` - Enable container-specific analysis
    * `--no-optimizations` - Skip optimization suggestions
  """

  @switches [
    output: :string,
    file: :string,
    domains: :string,
    threshold: :integer,
    container_mode: :boolean,
    optimizations: :boolean
  ]

  def run(args) do
    {opts, _, _} = OptionParser.parse(args, switches: @switches)
    
    # Ensure application is loaded
    Mix.Task.run("loadpaths")
    Mix.Task.run("compile", ["--no-deps-check"])
    
    # Convert and run analysis
    profiler_opts = convert_options(opts)
    AshProfiler.analyze(profiler_opts)
  end

  defp convert_options(opts) do
    converted = []
    
    converted = if opts[:output] do
      Keyword.put(converted, :output, String.to_atom(opts[:output]))
    else
      converted
    end
    
    converted = if opts[:file] do
      Keyword.put(converted, :file, opts[:file])
    else
      converted
    end
    
    converted = if opts[:domains] do
      domain_strings = String.split(opts[:domains], ",")
      domain_atoms = Enum.map(domain_strings, &Module.concat([String.trim(&1)]))
      Keyword.put(converted, :domains, domain_atoms)
    else
      converted
    end
    
    converted = if opts[:threshold], do: Keyword.put(converted, :threshold, opts[:threshold]), else: converted
    converted = if opts[:container_mode], do: Keyword.put(converted, :container_mode, true), else: converted
    converted = if opts[:optimizations] == false, do: Keyword.put(converted, :include_optimizations, false), else: converted
    
    converted
  end
end