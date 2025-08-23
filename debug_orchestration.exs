#!/usr/bin/env elixir

# Debug script for LANG orchestration system
# Run with: mix run debug_orchestration.exs

IO.puts("🚀 LANG Orchestration Debug Script")
IO.puts("==================================")

# Check if directories exist
directories = [
  "priv/static/docs/text",
  "priv/static/docs/filesystem",
  "priv/static/docs/cloud",
  "priv/static/docs/systems"
]

IO.puts("\n📁 Checking directory structure...")

Enum.each(directories, fn dir ->
  exists = File.exists?(dir)
  status = if exists, do: "✅", else: "❌"
  IO.puts("#{status} #{dir}")

  unless exists do
    File.mkdir_p!(dir)
    IO.puts("   Created directory: #{dir}")
  end
end)

# Test TextEnvironment worker directly
IO.puts("\n🔧 Testing TextEnvironment worker...")

try do
  # Test build_documentation task
  result = Lang.Workers.TextEnvironment.execute_task(:build_documentation, %{})
  IO.puts("✅ TextEnvironment.execute_task(:build_documentation) succeeded!")
  IO.inspect(result, label: "Result")

  # Check if files were created
  text_docs_dir = "priv/static/docs/text"

  if File.exists?(text_docs_dir) do
    files = File.ls!(text_docs_dir)
    IO.puts("\n📄 Generated documentation files:")

    Enum.each(files, fn file ->
      path = Path.join(text_docs_dir, file)
      size = File.stat!(path).size
      IO.puts("   #{file} (#{size} bytes)")
    end)
  else
    IO.puts("❌ No files found in #{text_docs_dir}")
  end
rescue
  error ->
    IO.puts("❌ TextEnvironment.execute_task failed:")
    IO.inspect(error, label: "Error")
end

# Check Oban configuration
IO.puts("\n⚙️  Checking Oban configuration...")

try do
  oban_config = Oban.config()
  IO.puts("✅ Oban is configured")
  IO.puts("   Repo: #{inspect(oban_config.repo)}")
  IO.puts("   Queues: #{inspect(oban_config.queues)}")
rescue
  error ->
    IO.puts("❌ Oban configuration error:")
    IO.inspect(error, label: "Error")
end

# Check current Oban jobs
IO.puts("\n📊 Checking Oban job status...")

try do
  # Query jobs without starting a transaction
  import Ecto.Query

  query =
    from(j in Oban.Job,
      select: %{state: j.state, queue: j.queue, worker: j.worker},
      order_by: [desc: j.inserted_at],
      limit: 20
    )

  jobs = Lang.Repo.all(query)

  if Enum.empty?(jobs) do
    IO.puts("   No recent Oban jobs found")
  else
    IO.puts("   Recent Oban jobs:")
    job_counts = Enum.group_by(jobs, & &1.state)

    Enum.each(job_counts, fn {state, jobs} ->
      IO.puts("   #{state}: #{length(jobs)} jobs")
    end)

    IO.puts("\n   Job details:")

    Enum.each(Enum.take(jobs, 5), fn job ->
      IO.puts("   - #{job.worker} (#{job.queue}) - #{job.state}")
    end)
  end
rescue
  error ->
    IO.puts("❌ Failed to query Oban jobs:")
    IO.inspect(error, label: "Error")
end

# Test orchestration master
IO.puts("\n🎭 Testing Orchestration Master...")

try do
  # Get orchestration status
  status = Lang.Orchestration.Master.get_status()
  IO.puts("✅ Orchestration Master is running")
  IO.inspect(status, label: "Status")
rescue
  error ->
    IO.puts("❌ Orchestration Master error:")
    IO.inspect(error, label: "Error")
end

# Test individual documentation generation functions
IO.puts("\n📝 Testing individual documentation generation...")

doc_functions = [
  :generate_intro_docs,
  :generate_quickstart_guide,
  :generate_api_reference,
  :generate_comprehensive_examples
]

Enum.each(doc_functions, fn func_name ->
  try do
    # Use apply to call private function through public interface
    result = apply(Lang.Workers.TextEnvironment, :execute_task, [:build_documentation, %{}])
    IO.puts("✅ Documentation generation working (tested via build_documentation)")
    break
  rescue
    error ->
      IO.puts("❌ #{func_name} failed:")
      IO.inspect(error, label: "Error")
  end
end)

# Test file writing permissions
IO.puts("\n✍️  Testing file writing permissions...")
test_file = "priv/static/docs/test_write.tmp"

try do
  File.write!(test_file, "Test content #{DateTime.utc_now()}")
  content = File.read!(test_file)
  File.rm!(test_file)
  IO.puts("✅ File writing permissions OK")
rescue
  error ->
    IO.puts("❌ File writing permission error:")
    IO.inspect(error, label: "Error")
end

# Summary
IO.puts("\n🎯 Debug Summary")
IO.puts("================")
IO.puts("1. Check directory structure - directories created if missing")
IO.puts("2. Test TextEnvironment worker - see results above")
IO.puts("3. Check Oban configuration - see status above")
IO.puts("4. Check Oban jobs - see job counts above")
IO.puts("5. Test Orchestration Master - see status above")
IO.puts("6. Test file writing - see permissions above")

IO.puts("\n💡 Next Steps:")

IO.puts(
  "   - If TextEnvironment works, try: Lang.Orchestration.Master.orchestrate_environment(:text)"
)

IO.puts("   - If jobs are failing, check specific error messages in Oban dashboard")
IO.puts("   - If file writing fails, check directory permissions")
IO.puts("   - Run: mix run -e 'Lang.Orchestration.Master.orchestrate_all()'")

IO.puts("\n🚀 Debug script completed!")
