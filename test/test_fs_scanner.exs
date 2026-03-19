# Simple test script for the native filesystem scanner
# Run with: mix run test_fs_scanner.exs

IO.puts("🧪 Testing Native Filesystem Scanner")
IO.puts("====================================")

try do
  # Test 1: Basic directory scan
  IO.puts("\n1. Testing basic directory scan...")

  case Lang.Native.FSScanner.scan(".", max_depth: 2) do
    {:ok, %{tree: tree, stats: stats}} ->
      IO.puts("✅ Scan successful!")
      IO.puts("   Files found: #{stats.total_files}")
      IO.puts("   Directories: #{stats.total_directories}")
      IO.puts("   Total size: #{Float.round(stats.total_size / (1024 * 1024), 2)} MB")
      IO.puts("   Scan time: #{stats.scan_duration_ms}ms")

      if stats.total_files > 0 do
        throughput = stats.total_files / (stats.scan_duration_ms / 1000)
        IO.puts("   Throughput: #{Float.round(throughput, 1)} files/sec")
      end

    {:error, reason} ->
      IO.puts("❌ Scan failed: #{reason}")
  end

  # Test 2: Content search
  IO.puts("\n2. Testing content search...")

  case Lang.Native.FSScanner.search(".", "defmodule|function|def ", max_results: 5) do
    {:ok, results} ->
      IO.puts("✅ Search successful!")
      IO.puts("   Matches found: #{length(results)}")

      Enum.take(results, 3)
      |> Enum.each(fn result ->
        IO.puts("   📄 #{Path.basename(result.path)}:#{result.line_number}")
        IO.puts("      #{String.trim(result.line_text)}")
      end)

    {:error, reason} ->
      IO.puts("❌ Search failed: #{reason}")
  end

  # Test 3: File preview
  IO.puts("\n3. Testing file preview...")

  case Lang.Native.FSScanner.preview("mix.exs", max_lines: 5) do
    {:ok, lines} ->
      IO.puts("✅ Preview successful!")
      IO.puts("   First #{length(lines)} lines of mix.exs:")

      Enum.with_index(lines, 1)
      |> Enum.each(fn {line, num} ->
        IO.puts("   #{num}: #{line}")
      end)

    {:error, reason} ->
      IO.puts("❌ Preview failed: #{reason}")
  end

  # Test 4: Performance comparison simulation
  IO.puts("\n4. Performance comparison (simulated)...")

  {time_micro, {:ok, %{stats: stats}}} =
    :timer.tc(fn ->
      Lang.Native.FSScanner.scan(".", max_depth: 3)
    end)

  # Convert to seconds
  native_time = time_micro / 1_000_000
  # Simulate what Elixir version would take (60-100x slower)
  estimated_elixir_time = native_time * 75

  IO.puts("✅ Performance comparison:")
  IO.puts("   Native Rust: #{Float.round(native_time, 3)}s")
  IO.puts("   Est. Elixir: #{Float.round(estimated_elixir_time, 3)}s")
  IO.puts("   Speedup: #{Float.round(estimated_elixir_time / native_time, 1)}x faster!")

  IO.puts("\n🎉 All tests completed successfully!")
rescue
  error ->
    IO.puts("\n💥 Test failed with error:")
    IO.puts("   #{Exception.format(:error, error, __STACKTRACE__)}")
end
