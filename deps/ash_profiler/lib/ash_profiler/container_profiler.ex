defmodule AshProfiler.ContainerProfiler do
  @moduledoc """
  Profiles compilation performance in container environments
  """

  def analyze_container_environment do
    IO.puts("=== Container Environment Analysis ===")

    print_system_resources()
    print_erlang_vm_info()
    print_compilation_environment()
    analyze_file_system_performance()
    check_container_limits()
  end

  defp print_system_resources do
    IO.puts("\n--- System Resources ---")

    # Memory info
    try do
      {memory_output, _} = System.cmd("free", ["-h"], stderr_to_stdout: true)
      IO.puts("Memory:\n#{memory_output}")
    rescue
      _ -> IO.puts("Memory info not available (free command not found)")
    end

    # CPU info
    try do
      {cpu_output, _} = System.cmd("nproc", [], stderr_to_stdout: true)
      IO.puts("CPU cores: #{String.trim(cpu_output)}")
    rescue
      _ ->
        # Fallback to Erlang scheduler count
        IO.puts("CPU cores: #{System.schedulers()} (from Erlang)")
    end

    # Disk space
    try do
      {disk_output, _} = System.cmd("df", ["-h", "."], stderr_to_stdout: true)
      IO.puts("Disk space:\n#{disk_output}")
    rescue
      _ -> IO.puts("Disk info not available")
    end

    # Load average
    try do
      {load_output, _} = System.cmd("uptime", [], stderr_to_stdout: true)
      IO.puts("Load: #{String.trim(load_output)}")
    rescue
      _ -> IO.puts("Load average not available")
    end
  end

  defp print_erlang_vm_info do
    IO.puts("\n--- Erlang VM Info ---")
    IO.puts("Erlang version: #{System.otp_release()}")
    IO.puts("Elixir version: #{System.version()}")
    IO.puts("Schedulers: #{System.schedulers()}")
    IO.puts("Schedulers online: #{System.schedulers_online()}")

    # Memory usage
    memory_info = :erlang.memory()
    IO.puts("VM Memory:")
    IO.puts("  Total: #{format_mb(memory_info[:total])} MB")
    IO.puts("  Processes: #{format_mb(memory_info[:processes])} MB")
    IO.puts("  System: #{format_mb(memory_info[:system])} MB")
    IO.puts("  Atom: #{format_mb(memory_info[:atom])} MB")
    IO.puts("  Binary: #{format_mb(memory_info[:binary])} MB")
    IO.puts("  Code: #{format_mb(memory_info[:code])} MB")
    IO.puts("  ETS: #{format_mb(memory_info[:ets])} MB")

    # Process info
    process_count = length(:erlang.processes())
    IO.puts("Active processes: #{process_count}")

    # Check for memory pressure
    total_mb = format_mb(memory_info[:total])

    if total_mb > 1000 do
      IO.puts("⚠️  High VM memory usage: #{total_mb} MB")
    end
  end

  defp print_compilation_environment do
    IO.puts("\n--- Compilation Environment ---")
    IO.puts("Mix env: #{Mix.env()}")
    IO.puts("Working directory: #{File.cwd!()}")

    # Check for container-specific indicators
    if File.exists?("/.dockerenv") do
      IO.puts("✅ Running in Docker container")
    else
      IO.puts("❓ Container environment not detected")
    end

    # Check cgroup limits (Docker/Kubernetes)
    check_cgroup_limits()

    # Check build cache
    build_path = Mix.Project.build_path()
    IO.puts("Build path: #{build_path}")

    if File.exists?(build_path) do
      try do
        {size_output, _} = System.cmd("du", ["-sh", build_path], stderr_to_stdout: true)
        IO.puts("Build cache size: #{String.trim(size_output)}")
      rescue
        _ ->
          # Fallback: count files
          file_count = count_files_recursive(build_path)
          IO.puts("Build cache files: #{file_count}")
      end
    else
      IO.puts("No build cache found")
    end

    # Check deps directory
    deps_path = Mix.Project.deps_path()

    if File.exists?(deps_path) do
      try do
        {size_output, _} = System.cmd("du", ["-sh", deps_path], stderr_to_stdout: true)
        IO.puts("Dependencies size: #{String.trim(size_output)}")
      rescue
        _ -> IO.puts("Dependencies directory exists but size unknown")
      end
    end
  end

  defp check_cgroup_limits do
    # Check memory limits
    memory_limit_file = "/sys/fs/cgroup/memory/memory.limit_in_bytes"

    if File.exists?(memory_limit_file) do
      try do
        limit = File.read!(memory_limit_file) |> String.trim() |> String.to_integer()
        # Convert to MB, handle very large values (no limit)
        if limit < 9_223_372_036_854_775_807 do
          limit_mb = div(limit, 1024 * 1024)
          IO.puts("Container memory limit: #{limit_mb} MB")

          if limit_mb < 2048 do
            IO.puts("⚠️  Low memory limit may impact compilation performance")
          end
        else
          IO.puts("Container memory: unlimited")
        end
      rescue
        _ -> IO.puts("Could not read memory limit")
      end
    end

    # Check CPU limits (cgroup v1)
    cpu_quota_file = "/sys/fs/cgroup/cpu/cpu.cfs_quota_us"
    cpu_period_file = "/sys/fs/cgroup/cpu/cpu.cfs_period_us"

    if File.exists?(cpu_quota_file) and File.exists?(cpu_period_file) do
      try do
        quota = File.read!(cpu_quota_file) |> String.trim() |> String.to_integer()
        period = File.read!(cpu_period_file) |> String.trim() |> String.to_integer()

        if quota > 0 do
          cpu_limit = quota / period
          IO.puts("Container CPU limit: #{Float.round(cpu_limit, 2)} cores")

          if cpu_limit < 2.0 do
            IO.puts("⚠️  Low CPU limit may slow compilation")
          end
        else
          IO.puts("Container CPU: unlimited")
        end
      rescue
        _ -> IO.puts("Could not read CPU limits")
      end
    end
  end

  defp analyze_file_system_performance do
    IO.puts("\n--- File System Performance ---")

    # Test file I/O performance
    test_file = "/tmp/compile_test_#{System.unique_integer()}.txt"
    test_data = String.duplicate("test data ", 1000)

    # Write test
    {write_time, _} =
      :timer.tc(fn ->
        File.write!(test_file, test_data)
      end)

    # Read test
    {read_time, _} =
      :timer.tc(fn ->
        File.read!(test_file)
      end)

    # Sync test (force write to disk)
    {sync_time, _} =
      :timer.tc(fn ->
        File.write!(test_file, test_data)
        # Try to sync if available
        try do
          System.cmd("sync", [])
        rescue
          _ -> :ok
        end
      end)

    File.rm(test_file)

    write_ms = write_time / 1000
    read_ms = read_time / 1000
    sync_ms = sync_time / 1000

    IO.puts("File I/O performance:")
    IO.puts("  Write: #{Float.round(write_ms, 2)} ms")
    IO.puts("  Read: #{Float.round(read_ms, 2)} ms")
    IO.puts("  Sync: #{Float.round(sync_ms, 2)} ms")

    # Flag slow I/O
    if write_ms > 10 or read_ms > 10 do
      IO.puts("⚠️  SLOW FILE I/O DETECTED - This will impact compilation significantly")
    end

    if sync_ms > 50 do
      IO.puts("⚠️  SLOW DISK SYNC - Container storage may be slow")
    end

    # Test directory operations (common during compilation)
    test_cpu_intensive_io()
  end

  defp test_cpu_intensive_io do
    IO.puts("\n--- CPU + I/O Combined Test ---")

    # Simulate compilation-like workload
    temp_dir = "/tmp/compile_sim_#{System.unique_integer()}"
    File.mkdir_p!(temp_dir)

    {total_time, _} =
      :timer.tc(fn ->
        # Create many small files (like .beam files)
        for i <- 1..50 do
          file_path = Path.join(temp_dir, "test_#{i}.txt")
          # Some CPU work + file write
          content = :crypto.hash(:sha256, "test#{i}") |> Base.encode64()
          File.write!(file_path, content)
        end
      end)

    File.rm_rf!(temp_dir)

    total_seconds = total_time / 1_000_000
    IO.puts("CPU+I/O simulation: #{Float.round(total_seconds, 3)} seconds")

    if total_seconds > 1.0 do
      IO.puts("⚠️  SLOW CPU+I/O - Compilation will be significantly impacted")
    end
  end

  defp check_container_limits do
    IO.puts("\n--- Container Resource Limits ---")

    # Check ulimits
    try do
      {ulimit_output, _} = System.cmd("ulimit", ["-a"], stderr_to_stdout: true)

      relevant_limits =
        ulimit_output
        |> String.split("\n")
        |> Enum.filter(fn line ->
          String.contains?(line, "open files") or
            String.contains?(line, "max memory") or
            String.contains?(line, "cpu time") or
            String.contains?(line, "virtual memory")
        end)

      if length(relevant_limits) > 0 do
        IO.puts("Resource limits:")
        Enum.each(relevant_limits, &IO.puts("  #{&1}"))
      end
    rescue
      _ -> IO.puts("Could not check ulimits")
    end

    # Check available entropy (can affect compilation randomness)
    try do
      {entropy_output, _} =
        System.cmd("cat", ["/proc/sys/kernel/random/entropy_avail"], stderr_to_stdout: true)

      entropy = String.trim(entropy_output) |> String.to_integer()
      IO.puts("Available entropy: #{entropy}")

      if entropy < 100 do
        IO.puts("⚠️  Low entropy - may slow cryptographic operations during compilation")
      end
    rescue
      _ -> IO.puts("Could not check entropy")
    end
  end

  defp format_mb(bytes) when is_integer(bytes) do
    Float.round(bytes / 1024 / 1024, 2)
  end

  defp count_files_recursive(dir) do
    try do
      Path.wildcard(Path.join(dir, "**/*"))
      |> Enum.count(&File.regular?/1)
    rescue
      _ -> 0
    end
  end

  def benchmark_compilation_environment do
    IO.puts("\n=== Compilation Environment Benchmark ===")

    # CPU benchmark
    {cpu_time, _} =
      :timer.tc(fn ->
        # Simulate macro expansion work
        Enum.reduce(1..100_000, %{}, fn i, acc ->
          Map.put(acc, "key_#{i}", i * 2)
        end)
      end)

    cpu_seconds = cpu_time / 1_000_000
    IO.puts("CPU benchmark: #{Float.round(cpu_seconds, 3)} seconds")

    # Memory allocation benchmark
    {memory_time, _} =
      :timer.tc(fn ->
        # Simulate AST building
        for _i <- 1..10_000 do
          %{
            type: :ast_node,
            children: Enum.map(1..10, &%{id: &1, value: "data_#{&1}"}),
            metadata: %{line: 1, file: "test.ex"}
          }
        end
      end)

    memory_seconds = memory_time / 1_000_000
    IO.puts("Memory allocation benchmark: #{Float.round(memory_seconds, 3)} seconds")

    # Combined score
    total_score = cpu_seconds + memory_seconds
    IO.puts("Combined performance score: #{Float.round(total_score, 3)} seconds")

    cond do
      total_score < 0.5 -> IO.puts("✅ Excellent performance")
      total_score < 1.0 -> IO.puts("✅ Good performance")
      total_score < 2.0 -> IO.puts("⚠️  Fair performance")
      true -> IO.puts("❌ Poor performance - compilation will be very slow")
    end

    total_score
  end
end
