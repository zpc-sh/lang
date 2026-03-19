defmodule Mix.Tasks.Dev.Clean do
  @moduledoc """
  Development cleanup and maintenance task for the LANG platform.

  This task combines common development cleanup operations in one convenient command.
  It's designed to be run regularly during development to maintain a clean workspace.

  ## Usage

      mix dev.clean

  ## Options

      --all          Run all cleanup operations (default)
      --artifacts    Only clean build artifacts
      --format       Only run code formatting
      --check        Only run pre-commit checks
      --deps         Reset dependencies
      --force        Skip confirmation prompts
      --quiet        Run in quiet mode

  ## Examples

      # Full development cleanup
      mix dev.clean

      # Quick artifact cleanup
      mix dev.clean --artifacts --force

      # Format code and run checks
      mix dev.clean --format --check

      # Reset everything for fresh start
      mix dev.clean --all --deps --force
  """

  @shortdoc "Comprehensive development cleanup and maintenance"

  use Mix.Task
  import Mix.Shell.IO, only: [info: 1, error: 1, yes?: 1]

  @switches [
    all: :boolean,
    artifacts: :boolean,
    format: :boolean,
    check: :boolean,
    deps: :boolean,
    force: :boolean,
    quiet: :boolean
  ]

  @aliases [
    a: :all,
    f: :force,
    q: :quiet
  ]

  def run(args) do
    {opts, _} = OptionParser.parse!(args, switches: @switches, aliases: @aliases)

    # Default to --all if no specific options provided
    opts = if no_action_specified?(opts), do: Keyword.put(opts, :all, true), else: opts

    unless opts[:quiet] do
      info("🚀 LANG Development Cleanup")
      info("=" |> String.duplicate(40))
    end

    # Execute requested operations
    if opts[:all] or opts[:artifacts] do
      clean_artifacts(opts)
    end

    if opts[:all] or opts[:deps] do
      reset_dependencies(opts)
    end

    if opts[:all] or opts[:format] do
      format_code(opts)
    end

    if opts[:all] or opts[:check] do
      run_checks(opts)
    end

    unless opts[:quiet] do
      info("")
      info("✅ Development cleanup completed!")
      print_next_steps(opts)
    end
  end

  defp no_action_specified?(opts) do
    actions = [:all, :artifacts, :format, :check, :deps]
    not Enum.any?(actions, &Keyword.get(opts, &1, false))
  end

  defp clean_artifacts(opts) do
    unless opts[:quiet], do: info("\n🧹 Cleaning build artifacts...")

    args = []
    args = if opts[:force], do: ["--force" | args], else: args
    args = if opts[:quiet], do: ["--quiet" | args], else: args

    case Mix.Tasks.Clean.Artifacts.run(args) do
      :ok -> :ok
      # Task handles its own output
      _ -> :ok
    end
  end

  defp reset_dependencies(opts) do
    unless opts[:quiet], do: info("\n📦 Resetting dependencies...")

    if opts[:force] or yes?("This will remove all dependencies and reinstall. Continue?") do
      # Clean existing deps
      if File.exists?("deps") do
        case File.rm_rf("deps") do
          {:ok, _} -> unless opts[:quiet], do: info("  ✓ Removed existing dependencies")
          {:error, reason} -> error("  ✗ Failed to remove deps: #{reason}")
        end
      end

      if File.exists?("_build") do
        case File.rm_rf("_build") do
          {:ok, _} -> unless opts[:quiet], do: info("  ✓ Removed build cache")
          {:error, reason} -> error("  ✗ Failed to remove _build: #{reason}")
        end
      end

      # Get fresh dependencies
      unless opts[:quiet], do: info("  📥 Fetching dependencies...")

      case System.cmd("mix", ["deps.get"], stderr_to_stdout: true) do
        {output, 0} ->
          unless opts[:quiet], do: info("  ✓ Dependencies updated successfully")

        {output, _} ->
          error("  ✗ Failed to fetch dependencies:")
          error(output)
      end

      # Compile dependencies
      unless opts[:quiet], do: info("  🔨 Compiling dependencies...")

      case System.cmd("mix", ["deps.compile"], stderr_to_stdout: true) do
        {_, 0} ->
          unless opts[:quiet], do: info("  ✓ Dependencies compiled successfully")

        {output, _} ->
          error("  ✗ Failed to compile dependencies:")
          error(output)
      end
    else
      info("  Dependency reset skipped")
    end
  end

  defp format_code(opts) do
    unless opts[:quiet], do: info("\n💅 Formatting code...")

    case System.cmd("mix", ["format"], stderr_to_stdout: true) do
      {_, 0} ->
        unless opts[:quiet], do: info("  ✓ Code formatted successfully")

      {output, _} ->
        error("  ✗ Code formatting failed:")
        error(output)
    end

    # Format assets if they exist
    if File.exists?("assets") do
      unless opts[:quiet], do: info("  🎨 Formatting JavaScript/CSS...")

      cond do
        File.exists?("assets/package.json") ->
          format_with_prettier(opts)

        true ->
          unless opts[:quiet], do: info("  ℹ️  No package.json found, skipping asset formatting")
      end
    end
  end

  defp format_with_prettier(opts) do
    case System.cmd("npm", ["run", "format"],
           stderr_to_stdout: true,
           cd: "assets"
         ) do
      {_, 0} ->
        unless opts[:quiet], do: info("    ✓ Assets formatted with prettier")

      {_, _} ->
        # Try installing prettier if not available
        case System.cmd("npx", ["prettier", "--write", "."],
               stderr_to_stdout: true,
               cd: "assets"
             ) do
          {_, 0} ->
            unless opts[:quiet], do: info("    ✓ Assets formatted with npx prettier")

          {_, _} ->
            unless opts[:quiet],
              do: info("    ℹ️  Prettier not available, skipping asset formatting")
        end
    end
  end

  defp run_checks(opts) do
    unless opts[:quiet], do: info("\n🔍 Running development checks...")

    args = []
    # Skip expensive checks in quiet mode
    args = if opts[:quiet], do: ["--skip-credo" | args], else: args

    case Mix.Tasks.Precommit.run(args) do
      :ok -> unless opts[:quiet], do: info("  ✓ All checks passed")
      _ -> unless opts[:quiet], do: info("  ⚠️  Some checks found issues (see above)")
    end
  end

  defp print_next_steps(opts) do
    info("")
    info("🎯 Next steps:")

    if opts[:all] or opts[:deps] do
      info("  • Your dependencies are fresh and compiled")
    end

    if opts[:all] or opts[:format] do
      info("  • Code has been formatted and is ready for commit")
    end

    info("  • Run 'mix phx.server' to start the development server")
    info("  • Run 'mix test' to ensure everything works")

    if opts[:all] do
      info("  • Run 'mix precommit' before committing changes")
    end

    info("")
    info("💡 Pro tip: Add 'alias dc=\"mix dev.clean\"' to your shell for quick access!")
  end
end
