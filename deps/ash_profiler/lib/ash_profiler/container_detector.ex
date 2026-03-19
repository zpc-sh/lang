defmodule AshProfiler.ContainerDetector do
  @moduledoc """
  Detects container environments and analyzes container-specific performance characteristics.
  """

  @doc """
  Detects if running in a container environment.
  """
  def in_container? do
    File.exists?("/.dockerenv") || 
    File.exists?("/proc/1/cgroup") && container_cgroup?() ||
    System.get_env("CONTAINER") != nil
  end

  @doc """
  Analyzes container environment for performance characteristics.
  """
  def analyze_container_environment do
    %{
      is_container: in_container?(),
      system_resources: analyze_system_resources(),
      performance_characteristics: analyze_performance_characteristics(),
      recommendations: generate_container_recommendations()
    }
  end

  defp container_cgroup? do
    case File.read("/proc/1/cgroup") do
      {:ok, content} -> String.contains?(content, "docker") || String.contains?(content, "container")
      {:error, _} -> false
    end
  end

  defp analyze_system_resources do
    %{
      memory: get_memory_info(),
      cpu: get_cpu_info(),
      disk: get_disk_info()
    }
  end

  defp get_memory_info do
    case System.cmd("free", ["-b"], stderr_to_stdout: true) do
      {output, 0} ->
        parse_memory_output(output)
      _ ->
        %{error: "Could not retrieve memory information"}
    end
  end

  defp parse_memory_output(output) do
    lines = String.split(output, "\n")
    mem_line = Enum.find(lines, &String.starts_with?(&1, "Mem:"))
    
    if mem_line do
      [_, total, used, free | _] = String.split(mem_line)
      
      %{
        total_bytes: String.to_integer(total),
        used_bytes: String.to_integer(used),
        free_bytes: String.to_integer(free),
        total_mb: div(String.to_integer(total), 1024 * 1024),
        used_mb: div(String.to_integer(used), 1024 * 1024),
        free_mb: div(String.to_integer(free), 1024 * 1024)
      }
    else
      %{error: "Could not parse memory information"}
    end
  end

  defp get_cpu_info do
    case System.cmd("nproc", [], stderr_to_stdout: true) do
      {output, 0} ->
        cpu_count = String.trim(output) |> String.to_integer()
        %{
          cpu_count: cpu_count,
          schedulers: System.schedulers(),
          schedulers_online: System.schedulers_online()
        }
      _ ->
        %{
          cpu_count: :unknown,
          schedulers: System.schedulers(),
          schedulers_online: System.schedulers_online()
        }
    end
  end

  defp get_disk_info do
    case System.cmd("df", ["-h", "."], stderr_to_stdout: true) do
      {output, 0} ->
        lines = String.split(output, "\n")
        data_line = Enum.at(lines, 1)
        
        if data_line do
          [_filesystem, size, used, available | _] = String.split(data_line)
          %{
            total: size,
            used: used,
            available: available
          }
        else
          %{error: "Could not parse disk information"}
        end
      _ ->
        %{error: "Could not retrieve disk information"}
    end
  end

  defp analyze_performance_characteristics do
    %{
      file_io_performance: test_file_io_performance(),
      memory_pressure: detect_memory_pressure(),
      cpu_throttling: detect_cpu_throttling()
    }
  end

  defp test_file_io_performance do
    test_file = "/tmp/ash_profiler_io_test_#{System.unique_integer()}"
    test_data = String.duplicate("test data\n", 1000)
    
    # Write test
    {write_time, _} = :timer.tc(fn ->
      File.write!(test_file, test_data)
    end)
    
    # Read test
    {read_time, _} = :timer.tc(fn ->
      File.read!(test_file)
    end)
    
    File.rm(test_file)
    
    %{
      write_time_microseconds: write_time,
      read_time_microseconds: read_time,
      write_time_ms: div(write_time, 1000),
      read_time_ms: div(read_time, 1000),
      performance_rating: rate_io_performance(write_time, read_time)
    }
  end

  defp rate_io_performance(write_time, read_time) do
    avg_time = div(write_time + read_time, 2)
    
    cond do
      avg_time < 1000 -> :excellent  # < 1ms
      avg_time < 5000 -> :good       # < 5ms
      avg_time < 10000 -> :fair      # < 10ms
      true -> :poor                  # > 10ms
    end
  end

  defp detect_memory_pressure do
    vm_memory = :erlang.memory()
    total_memory = vm_memory[:total]
    
    # Simple heuristic for memory pressure detection
    %{
      vm_total_mb: div(total_memory, 1024 * 1024),
      pressure_detected: total_memory > 100 * 1024 * 1024  # > 100MB indicates potential pressure
    }
  end

  defp detect_cpu_throttling do
    # Simple CPU performance test
    {time, _} = :timer.tc(fn ->
      # CPU-intensive task
      Enum.reduce(1..100_000, 0, &+/2)
    end)
    
    %{
      test_time_microseconds: time,
      test_time_ms: div(time, 1000),
      throttling_suspected: time > 100_000  # > 100ms suggests throttling
    }
  end

  defp generate_container_recommendations do
    base_recommendations = []
    
    if in_container?() do
      recommendations = [
        "🚀 CRITICAL: Set ELIXIR_ERL_OPTIONS=\"+sbwt none +sbwtdcpu none +sbwtdio none\"",
        "🚀 CRITICAL: Increase container memory to at least 4GB (8GB recommended)",
        "⚡ HIGH IMPACT: Enable ASH_DISABLE_COMPILE_DEPENDENCY_TRACKING=true",
        "⚡ HIGH IMPACT: Use multi-stage Docker builds with proper caching",
        "🔧 OPTIMIZATION: Set ERL_FLAGS=\"+S 4:4 +P 1048576\" for scheduler tuning",
        "🔧 OPTIMIZATION: Enable Docker BuildKit for better layer caching",
        "📊 MONITORING: Compare compilation times in container vs local environment",
        "",
        "💡 QUICK START: Run 'AshProfiler.DockerOptimizer.generate_dockerfile()' for optimized Dockerfile"
        | base_recommendations
      ]
      
      # Add specific recommendations based on detected container type
      recommendations ++ detect_container_specific_optimizations()
    else
      base_recommendations
    end
  end

  defp detect_container_specific_optimizations do
    optimizations = []
    
    # Check for Kubernetes environment
    optimizations = if System.get_env("KUBERNETES_SERVICE_HOST") do
      ["🎯 KUBERNETES: Set resource limits in pod specs for predictable performance" | optimizations]
    else
      optimizations
    end
    
    # Check for GitHub Actions
    optimizations = if System.get_env("GITHUB_ACTIONS") do
      ["🎯 GITHUB ACTIONS: Use 'actions/cache' for Docker layer caching" | optimizations] 
    else
      optimizations
    end
    
    # Check for GitLab CI
    optimizations = if System.get_env("GITLAB_CI") do
      ["🎯 GITLAB CI: Enable Docker-in-Docker with proper caching strategy" | optimizations]
    else
      optimizations
    end
    
    optimizations
  end
end