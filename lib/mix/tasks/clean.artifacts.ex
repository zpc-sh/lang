defmodule Mix.Tasks.Clean.Artifacts do
  @moduledoc """
  Cleans all build artifacts for the LANG Universal Text Intelligence Platform.

  This task removes:
  - Mix build artifacts (_build/, deps/, cover/, doc/, tmp/)
  - Phoenix assets (priv/static/assets/, cache_manifest.json)
  - Node.js artifacts (node_modules/, package-lock.json)
  - Rust native artifacts (target/, Cargo.lock, compiled libraries)
  - IDE and OS files (.vscode/, .idea/, .DS_Store, etc.)
  - Log files, temporary files, and backup files
  - Test coverage and documentation artifacts
  - Release and deployment artifacts

  ## Usage

      mix clean.artifacts

  ## Options

      --force    Skip confirmation prompt
      --quiet    Run in quiet mode with minimal output
      --dry-run  Show what would be cleaned without actually deleting

  ## Examples

      # Clean with confirmation
      mix clean.artifacts

      # Clean without confirmation
      mix clean.artifacts --force

      # See what would be cleaned
      mix clean.artifacts --dry-run
  """

  @shortdoc "Cleans all build artifacts and temporary files"

  use Mix.Task
  import Mix.Shell.IO, only: [info: 1, error: 1, yes?: 1]

  @switches [
    force: :boolean,
    quiet: :boolean,
    dry_run: :boolean
  ]

  @aliases [
    f: :force,
    q: :quiet,
    d: :dry_run
  ]

  def run(args) do
    {opts, _} = OptionParser.parse!(args, switches: @switches, aliases: @aliases)

    if opts[:dry_run] do
      info("🔍 Dry run mode - showing what would be cleaned:")
      list_cleanup_targets()
    else
      unless opts[:force] do
        unless yes?("🧹 This will remove all build artifacts. Continue?") do
          info("Cleanup cancelled.")
          :ok
        end
      end

      clean_artifacts(opts)
    end
  end

  defp clean_artifacts(opts) do
    quiet = opts[:quiet]

    unless quiet, do: info("🧹 Cleaning LANG build artifacts...")

    # Track cleaned items
    cleaned_count = 0
    cleaned_count = cleaned_count + clean_mix_artifacts(quiet)
    cleaned_count = cleaned_count + clean_phoenix_assets(quiet)
    cleaned_count = cleaned_count + clean_nodejs_artifacts(quiet)
    cleaned_count = cleaned_count + clean_rust_artifacts(quiet)
    cleaned_count = cleaned_count + clean_compiled_libraries(quiet)
    cleaned_count = cleaned_count + clean_ide_os_files(quiet)
    cleaned_count = cleaned_count + clean_logs_temp_files(quiet)
    cleaned_count = cleaned_count + clean_test_artifacts(quiet)
    cleaned_count = cleaned_count + clean_dev_artifacts(quiet)
    cleaned_count = cleaned_count + clean_release_artifacts(quiet)
    cleaned_count = cleaned_count + clean_documentation(quiet)
    cleaned_count = cleaned_count + clean_benchmarking_profiling(quiet)

    unless quiet do
      info("✅ Cleanup complete! Removed #{cleaned_count} items.")
      info("")
      info("To rebuild everything:")
      info("  mix deps.get")
      info("  cd assets && npm install")
      info("  mix compile")
      info("")
      info("To rebuild native extensions:")
      info("  mix deps.compile --force")
    end
  end

  defp clean_mix_artifacts(quiet) do
    unless quiet, do: info("  • Cleaning Mix artifacts...")

    paths = [
      "_build/",
      "cover/",
      "deps/",
      "doc/",
      "tmp/"
    ]

    files = [
      "*.ez",
      "lang-*.tar",
      "erl_crash.dump"
    ]

    remove_paths(paths) + remove_files(files)
  end

  defp clean_phoenix_assets(quiet) do
    unless quiet, do: info("  • Cleaning Phoenix assets...")

    paths = [
      "priv/static/assets/",
      "priv/uploads/"
    ]

    files = [
      "priv/static/cache_manifest.json"
    ]

    remove_paths(paths) + remove_files(files)
  end

  defp clean_nodejs_artifacts(quiet) do
    unless quiet, do: info("  • Cleaning Node.js artifacts...")

    paths = [
      "assets/node_modules/"
    ]

    files = [
      "assets/package-lock.json",
      "assets/yarn.lock",
      "npm-debug.log"
    ]

    remove_paths(paths) + remove_files(files)
  end

  defp clean_rust_artifacts(quiet) do
    unless quiet, do: info("  • Cleaning Rust native artifacts...")

    # Find and remove target directories
    target_dirs = find_directories("native/*/target")
    target_count = remove_paths(target_dirs)

    # Find and remove Cargo.lock files
    cargo_locks = find_files("native/*/Cargo.lock")
    cargo_count = remove_files(cargo_locks)

    # Clean other rust artifacts
    paths = [
      "priv/native/",
      "priv/crates/",
      "priv/precompiled_nifs/"
    ]

    files = [
      "checksum-*.exs"
    ]

    target_count + cargo_count + remove_paths(paths) + remove_files(files)
  end

  defp clean_compiled_libraries(quiet) do
    unless quiet, do: info("  • Cleaning compiled libraries...")

    extensions = ["*.so", "*.dll", "*.dylib"]

    Enum.reduce(extensions, 0, fn ext, acc ->
      acc + remove_files([ext])
    end)
  end

  defp clean_ide_os_files(quiet) do
    unless quiet, do: info("  • Cleaning IDE and OS files...")

    paths = [
      ".vscode/",
      ".idea/"
    ]

    files = [
      "*.swp",
      "*.swo",
      "*~",
      ".DS_Store",
      "Thumbs.db"
    ]

    remove_paths(paths) + remove_files(files)
  end

  defp clean_logs_temp_files(quiet) do
    unless quiet, do: info("  • Cleaning logs and temporary files...")

    paths = [
      "logs/",
      "log/"
    ]

    files = [
      "*.log",
      "*.tmp",
      "*.temp",
      "*.bak",
      "*.backup"
    ]

    remove_paths(paths) + remove_files(files)
  end

  defp clean_test_artifacts(quiet) do
    unless quiet, do: info("  • Cleaning test artifacts...")

    paths = [
      "coverage/"
    ]

    files = [
      "lcov.info"
    ]

    remove_paths(paths) + remove_files(files)
  end

  defp clean_dev_artifacts(quiet) do
    unless quiet, do: info("  • Cleaning development artifacts...")

    paths = [
      ".elixir_ls/",
      ".lexical/"
    ]

    remove_paths(paths)
  end

  defp clean_release_artifacts(quiet) do
    unless quiet, do: info("  • Cleaning release artifacts...")

    paths = [
      "_rel/",
      "rel/"
    ]

    files = [
      "*.tar.gz"
    ]

    remove_paths(paths) + remove_files(files)
  end

  defp clean_documentation(quiet) do
    unless quiet, do: info("  • Cleaning documentation...")

    paths = [
      "docs/",
      "documentation/"
    ]

    remove_paths(paths)
  end

  defp clean_benchmarking_profiling(quiet) do
    unless quiet, do: info("  • Cleaning benchmarking and profiling data...")

    paths = [
      "benchmarks/results/"
    ]

    files = [
      "*.bench",
      "*.prof"
    ]

    remove_paths(paths) + remove_files(files)
  end

  # Helper functions for file operations
  defp remove_paths(paths) do
    Enum.reduce(paths, 0, fn path, acc ->
      if File.exists?(path) do
        case File.rm_rf(path) do
          {:ok, _} -> acc + 1
          {:error, _} -> acc
        end
      else
        acc
      end
    end)
  end

  defp remove_files(patterns) do
    Enum.reduce(patterns, 0, fn pattern, acc ->
      files = Path.wildcard(pattern)

      Enum.reduce(files, acc, fn file, file_acc ->
        case File.rm(file) do
          :ok -> file_acc + 1
          {:error, _} -> file_acc
        end
      end)
    end)
  end

  defp find_directories(pattern) do
    Path.wildcard(pattern)
    |> Enum.filter(&File.dir?/1)
  end

  defp find_files(pattern) do
    Path.wildcard(pattern)
    |> Enum.filter(&File.regular?/1)
  end

  defp list_cleanup_targets do
    info("The following would be cleaned:")
    info("")

    # Mix artifacts
    info("Mix artifacts:")
    list_existing_paths(["_build/", "cover/", "deps/", "doc/", "tmp/"])
    list_existing_files(["*.ez", "lang-*.tar", "erl_crash.dump"])

    # Phoenix assets
    info("Phoenix assets:")
    list_existing_paths(["priv/static/assets/", "priv/uploads/"])
    list_existing_files(["priv/static/cache_manifest.json"])

    # Node.js artifacts
    info("Node.js artifacts:")
    list_existing_paths(["assets/node_modules/"])
    list_existing_files(["assets/package-lock.json", "assets/yarn.lock", "npm-debug.log"])

    # Rust artifacts
    info("Rust native artifacts:")
    list_existing_paths(find_directories("native/*/target"))
    list_existing_files(find_files("native/*/Cargo.lock"))
    list_existing_paths(["priv/native/", "priv/crates/", "priv/precompiled_nifs/"])
    list_existing_files(["checksum-*.exs"])

    # Compiled libraries
    info("Compiled libraries:")
    list_existing_files(["*.so", "*.dll", "*.dylib"])

    # IDE/OS files
    info("IDE and OS files:")
    list_existing_paths([".vscode/", ".idea/"])
    list_existing_files(["*.swp", "*.swo", "*~", ".DS_Store", "Thumbs.db"])

    # Logs and temp files
    info("Logs and temporary files:")
    list_existing_paths(["logs/", "log/"])
    list_existing_files(["*.log", "*.tmp", "*.temp", "*.bak", "*.backup"])

    info("")
  end

  defp list_existing_paths(paths) do
    for path <- paths do
      if File.exists?(path) do
        info("  - #{path}")
      end
    end
  end

  defp list_existing_files(patterns) do
    for pattern <- patterns do
      files = Path.wildcard(pattern)

      for file <- files do
        info("  - #{file}")
      end
    end
  end
end
