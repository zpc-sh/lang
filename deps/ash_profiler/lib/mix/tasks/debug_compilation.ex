defmodule Mix.Tasks.DebugCompilation do
  use Mix.Task

  @shortdoc "Debug Ash DSL compilation performance"
  @moduledoc """
  Comprehensive analysis of Ash DSL compilation performance issues.

  Usage:
    mix debug_compilation
    mix debug_compilation --container-mode
    mix debug_compilation --profile-only
    mix debug_compilation --benchmark
  """

  def run(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        switches: [container_mode: :boolean, profile_only: :boolean, benchmark: :boolean]
      )

    IO.puts("🔍 Starting Ash DSL Compilation Debug")
    IO.puts("Environment: #{if opts[:container_mode], do: "Container", else: "Local"}")
    IO.puts("Time: #{DateTime.utc_now()}")

    # Ensure application is loaded but not started
    Mix.Task.run("loadpaths")

    # Load app modules for introspection
    try do
      Mix.Task.run("compile", ["--no-deps-check"])
    rescue
      error ->
        IO.puts("⚠️  Compilation failed during setup: #{inspect(error)}")
        IO.puts("Continuing with available modules...")
    end

    # Run container analysis if requested
    if opts[:container_mode] do
      AshProfiler.ContainerProfiler.analyze_container_environment()

      # Run performance benchmark
      if opts[:benchmark] do
        score = AshProfiler.ContainerProfiler.benchmark_compilation_environment()

        if score > 2.0 do
          IO.puts(
            "\n🚨 PERFORMANCE ALERT: Container environment is too slow for efficient compilation"
          )
        end
      end
    end

    # Run DSL profiling unless profile-only is disabled
    unless opts[:profile_only] == false do
      AshProfiler.DSLProfiler.profile_dsl_compilation()
    end

    # Run targeted compilation tests
    run_compilation_tests()

    # Analyze specific Ash patterns
    analyze_ash_patterns()

    # Generate recommendations
    generate_recommendations(opts)

    IO.puts("✅ Debug analysis complete")
  end

  defp run_compilation_tests do
    IO.puts("\n=== Running Compilation Tests ===")

    # Test clean compilation
    IO.puts("\nTesting clean compilation...")

    # Clear build but preserve deps
    File.rm_rf(Mix.Project.build_path())

    {compile_time, {output, _exit_code}} =
      :timer.tc(fn ->
        System.cmd("mix", ["compile", "--force", "--all-warnings"],
          stderr_to_stdout: true,
          cd: File.cwd!()
        )
      end)

    compile_seconds = compile_time / 1_000_000
    IO.puts("Clean compilation time: #{Float.round(compile_seconds, 2)} seconds")

    if compile_seconds > 300 do
      IO.puts("⚠️  SLOW COMPILATION DETECTED (> 5 minutes)")

      # Look for specific slow patterns in output
      if String.contains?(output, "Compiling") do
        slow_files = extract_slow_compiling_files(output)

        if length(slow_files) > 0 do
          IO.puts("Slowest files to compile:")
          Enum.each(slow_files, &IO.puts("  - #{&1}"))
        end
      end
    end

    # Test incremental compilation
    IO.puts("\nTesting incremental compilation...")

    {incremental_time, _} =
      :timer.tc(fn ->
        System.cmd("mix", ["compile"], stderr_to_stdout: true, cd: File.cwd!())
      end)

    incremental_seconds = incremental_time / 1_000_000
    IO.puts("Incremental compilation time: #{Float.round(incremental_seconds, 2)} seconds")

    # Analyze compilation ratio
    if incremental_seconds > 0 do
      ratio = compile_seconds / incremental_seconds
      IO.puts("Clean/Incremental ratio: #{Float.round(ratio, 1)}x")

      if ratio < 5 do
        IO.puts("⚠️  Poor incremental compilation performance")
      end
    end
  end

  defp extract_slow_compiling_files(output) do
    # Extract file names that might be causing slowdowns
    output
    |> String.split("\n")
    |> Enum.filter(&String.contains?(&1, "Compiling"))
    |> Enum.map(fn line ->
      # Extract file names from compilation output
      case Regex.run(~r/Compiling\s+.*\s+\((.*)\)/, line) do
        [_, file] ->
          file

        _ ->
          case Regex.run(~r/==>\s+Compiling\s+(.*)/, line) do
            [_, app] -> app
            _ -> line
          end
      end
    end)
    # Top 5
    |> Enum.take(5)
  end

  defp analyze_ash_patterns do
    IO.puts("\n=== Analyzing Ash-Specific Patterns ===")

    # Check for common performance issues
    check_for_common_ash_issues()

    # Analyze resource interdependencies
    analyze_resource_dependencies()

    # Check for expensive validations
    check_expensive_validations()
  end

  defp check_for_common_ash_issues do
    IO.puts("\nChecking for known Ash performance issues...")

    issues_found =
      []
      |> check_state_machine_resources()
      |> check_complex_policies()
      |> check_relationship_heavy_resources()
      |> check_circular_resource_deps()
      |> check_expensive_computed_attributes()

    if length(issues_found) == 0 do
      IO.puts("✅ No obvious Ash performance issues found")
    end

    issues_found
  end

  defp check_state_machine_resources(issues_found) do
    if has_state_machine_resources?() do
      IO.puts("⚠️  AshStateMachine detected - known to slow compilation significantly")
      ["state_machine" | issues_found]
    else
      issues_found
    end
  end

  defp check_complex_policies(issues_found) do
    if has_complex_policies?() do
      IO.puts("⚠️  Complex authorization policies detected")
      ["complex_policies" | issues_found]
    else
      issues_found
    end
  end

  defp check_relationship_heavy_resources(issues_found) do
    heavy_resources = find_relationship_heavy_resources()

    if length(heavy_resources) > 0 do
      IO.puts("⚠️  Resources with many relationships detected:")

      Enum.each(heavy_resources, fn {file, count} ->
        IO.puts("    #{file}: #{count} relationships")
      end)

      ["many_relationships" | issues_found]
    else
      issues_found
    end
  end

  defp check_circular_resource_deps(issues_found) do
    if has_circular_resource_deps?() do
      IO.puts("⚠️  Potential circular resource dependencies detected")
      ["circular_deps" | issues_found]
    else
      issues_found
    end
  end

  defp check_expensive_computed_attributes(issues_found) do
    if has_expensive_computed_attributes?() do
      IO.puts("⚠️  Expensive computed attributes detected")
      ["expensive_computed" | issues_found]
    else
      issues_found
    end
  end

  defp analyze_resource_dependencies do
    IO.puts("\nAnalyzing resource dependency graph...")

    # Find all resource files
    resource_files = find_ash_resource_files()

    # Build dependency map
    deps = build_resource_dependency_map(resource_files)

    # Look for complex dependency patterns
    complex_deps =
      Enum.filter(deps, fn {_resource, resource_deps} ->
        length(resource_deps) > 5
      end)

    if length(complex_deps) > 0 do
      IO.puts("Resources with many dependencies:")

      Enum.each(complex_deps, fn {resource, resource_deps} ->
        IO.puts("  #{resource}: depends on #{length(resource_deps)} other resources")
      end)
    end

    # Check for mutual dependencies
    mutual_deps = find_mutual_dependencies(deps)

    if length(mutual_deps) > 0 do
      IO.puts("⚠️  Mutual dependencies found:")

      Enum.each(mutual_deps, fn {a, b} ->
        IO.puts("    #{a} ↔ #{b}")
      end)
    end
  end

  defp check_expensive_validations do
    IO.puts("\nChecking for expensive validations...")

    # Look for validations that might be slow
    expensive_patterns = [
      ~r/validate.*Enum\.all\?/,
      ~r/validate.*Enum\.any\?/,
      ~r/validate.*Repo\.get/,
      ~r/validate.*Repo\.exists\?/,
      ~r/change.*Repo\./,
      ~r/validate.*HTTPoison/,
      ~r/validate.*Req\./
    ]

    Path.wildcard("lib/**/*.ex")
    |> Enum.each(fn file ->
      content = File.read!(file)

      for pattern <- expensive_patterns do
        if Regex.match?(pattern, content) do
          matches = Regex.scan(pattern, content) |> length()

          if matches > 0 do
            IO.puts("⚠️  #{file}: #{matches} potentially expensive validations")
          end
        end
      end
    end)
  end

  defp generate_recommendations(opts) do
    IO.puts("\n=== 🔧 Performance Recommendations ===")

    container_mode = opts[:container_mode]

    if container_mode do
      IO.puts("\n📦 Container-Specific Optimizations:")
      IO.puts("  • Increase container memory limit (minimum 4GB for Ash projects)")
      IO.puts("  • Use multi-stage Docker builds with compilation cache")
      IO.puts("  • Set ELIXIR_ERL_OPTIONS=\"+sbwt none +sbwtdcpu none +sbwtdio none\"")
      IO.puts("  • Consider using BuildKit with cache mounts")
      IO.puts("  • Use faster storage (avoid shared volumes for compilation)")
    end

    IO.puts("\n⚡ Ash DSL Optimizations:")
    IO.puts("  • Split large resources into smaller, focused resources")
    IO.puts("  • Move complex computed attributes to separate modules")
    IO.puts("  • Simplify authorization policy expressions")
    IO.puts("  • Reduce relationship count per resource (< 10 recommended)")
    IO.puts("  • Use lazy-loaded relationships where possible")

    IO.puts("\n🚀 Compilation Optimizations:")
    IO.puts("  • Set ASH_DISABLE_COMPILE_DEPENDENCY_TRACKING=true in dev")
    IO.puts("  • Use mix compile.ash --no-deps-check for faster rebuilds")
    IO.puts("  • Consider splitting domains by compilation independence")
    IO.puts("  • Cache _build directory in CI/CD pipelines")

    IO.puts("\n🛠️  Development Workflow:")
    IO.puts("  • Use mix compile.ash --watch for development")
    IO.puts("  • Create simplified resource definitions for test env")
    IO.puts("  • Use --parallel flag: mix compile --parallel")

    # Check current Mix environment
    if Mix.env() == :prod do
      IO.puts("\n🏭 Production Build Optimizations:")
      IO.puts("  • MIX_ENV=prod mix compile --no-debug-info")
      IO.puts("  • Use mix release for optimized production builds")
      IO.puts("  • Enable compiler optimizations with --optimize")
    end

    # Environment-specific suggestions
    if container_mode do
      suggest_container_dockerfile()
    else
      suggest_local_optimizations()
    end
  end

  defp suggest_container_dockerfile do
    IO.puts("\n🐳 Suggested Dockerfile optimizations:")

    IO.puts("""
    # Multi-stage build with dependency caching
    FROM elixir:1.15-alpine AS deps
    WORKDIR /app
    COPY mix.exs mix.lock ./
    RUN mix deps.get --only=prod

    FROM elixir:1.15-alpine AS build
    WORKDIR /app
    ENV MIX_ENV=prod
    ENV ELIXIR_ERL_OPTIONS="+sbwt none +sbwtdcpu none +sbwtdio none"
    COPY --from=deps /app/deps deps/
    COPY . .
    RUN mix compile --no-deps-check --force
    """)
  end

  defp suggest_local_optimizations do
    IO.puts("\n💻 Local development optimizations:")

    IO.puts(
      "  • Add to .bashrc: export ELIXIR_ERL_OPTIONS=\"+sbwt none +sbwtdcpu none +sbwtdio none\""
    )

    IO.puts("  • Use: mix compile --parallel")
    IO.puts("  • Consider using: mix compile.ash --no-compile-dependencies")
    IO.puts("  • For VSCode: disable Elixir LS on_type_formatting")
  end

  # Helper functions for analysis
  defp has_state_machine_resources?() do
    grep_pattern("AshStateMachine")
  end

  defp has_complex_policies?() do
    grep_pattern("authorize_if") && (grep_pattern(" and ") || grep_pattern(" or "))
  end

  defp find_relationship_heavy_resources() do
    Path.wildcard("lib/**/*.ex")
    |> Enum.map(fn file ->
      content = File.read!(file)
      relationship_count = count_relationships(content)
      {file, relationship_count}
    end)
    |> Enum.filter(fn {_file, count} -> count > 8 end)
    |> Enum.sort_by(fn {_file, count} -> -count end)
  end

  defp has_circular_resource_deps?() do
    # Simple heuristic: look for resources that import each other
    resource_files = find_ash_resource_files()

    Enum.any?(resource_files, fn file ->
      content = File.read!(file)
      other_resources = resource_files -- [file]

      Enum.count(other_resources, fn other_file ->
        resource_name = extract_resource_name(other_file)
        String.contains?(content, resource_name)
      end) > 3
    end)
  end

  defp has_expensive_computed_attributes?() do
    grep_pattern("calculate") && (grep_pattern("Repo.") || grep_pattern("Enum."))
  end

  defp find_ash_resource_files() do
    Path.wildcard("lib/**/*.ex")
    |> Enum.filter(fn file ->
      content = File.read!(file)
      String.contains?(content, "use Ash.Resource")
    end)
  end

  defp build_resource_dependency_map(resource_files) do
    Enum.map(resource_files, fn file ->
      content = File.read!(file)
      resource_name = extract_resource_name(file)

      # Find dependencies by looking for other resource references
      deps =
        resource_files
        |> Enum.reject(&(&1 == file))
        |> Enum.filter(fn other_file ->
          other_resource = extract_resource_name(other_file)
          String.contains?(content, other_resource)
        end)
        |> Enum.map(&extract_resource_name/1)

      {resource_name, deps}
    end)
  end

  defp find_mutual_dependencies(deps) do
    # Find pairs where A depends on B and B depends on A
    for {resource_a, deps_a} <- deps,
        {resource_b, deps_b} <- deps,
        # Avoid duplicates
        resource_a < resource_b,
        resource_b in deps_a,
        resource_a in deps_b do
      {resource_a, resource_b}
    end
  end

  defp count_relationships(content) do
    relationship_patterns = [~r/belongs_to/, ~r/has_many/, ~r/has_one/, ~r/many_to_many/]

    Enum.sum(
      Enum.map(relationship_patterns, fn pattern ->
        length(Regex.scan(pattern, content))
      end)
    )
  end

  defp extract_resource_name(file_path) do
    file_path
    |> Path.basename(".ex")
    |> String.split("_")
    |> Enum.map(&String.capitalize/1)
    |> Enum.join("")
  end

  defp grep_pattern(pattern) do
    try do
      {output, _} = System.cmd("grep", ["-r", pattern, "lib/"], stderr_to_stdout: true)
      String.trim(output) != ""
    rescue
      _ -> false
    end
  end
end
