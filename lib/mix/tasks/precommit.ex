defmodule Mix.Tasks.Precommit do
  @moduledoc """
  Pre-commit validation for the LANG Universal Text Intelligence Platform.

  This task prevents committing build artifacts, secrets, and other sensitive files.
  It also runs code formatting and static analysis checks.

  ## Usage

      mix precommit

  ## Options

      --fix      Attempt to fix formatting issues automatically
      --skip-format    Skip Elixir code formatting checks
      --skip-credo     Skip Credo static analysis
      --skip-secrets   Skip secret detection
      --force          Continue even if issues are found (not recommended)

  ## Examples

      # Run all pre-commit checks
      mix precommit

      # Run with auto-fix for formatting
      mix precommit --fix

      # Skip expensive checks for quick validation
      mix precommit --skip-credo

      # Force commit (bypasses all checks - use with caution)
      mix precommit --force
  """

  @shortdoc "Runs pre-commit validation checks"

  use Mix.Task
  import Mix.Shell.IO, only: [info: 1, error: 1, cmd: 1]
  import Bitwise

  @switches [
    fix: :boolean,
    skip_format: :boolean,
    skip_credo: :boolean,
    skip_secrets: :boolean,
    force: :boolean
  ]

  @aliases [
    f: :fix
  ]

  def run(args) do
    {opts, _} = OptionParser.parse!(args, switches: @switches, aliases: @aliases)

    info("🔍 Running pre-commit checks...")

    if opts[:force] do
      info("⚠️  Force mode enabled - skipping all checks")
      System.halt(0)
    end

    issues_found = 0
    issues_found = issues_found + check_staged_files()
    issues_found = issues_found + check_build_artifacts()
    issues_found = issues_found + check_large_files()
    issues_found = issues_found + check_file_permissions()

    unless opts[:skip_secrets] do
      issues_found = issues_found + check_secrets()
    end

    unless opts[:skip_format] do
      issues_found = issues_found + check_elixir_formatting(opts[:fix])
    end

    unless opts[:skip_credo] do
      issues_found = issues_found + check_credo()
    end

    print_summary(issues_found)

    if issues_found > 0 do
      System.halt(1)
    end
  end

  defp check_staged_files do
    case System.cmd("git", ["diff", "--cached", "--name-only"], stderr_to_stdout: true) do
      {output, 0} ->
        staged_files = String.split(output, "\n", trim: true)

        if Enum.empty?(staged_files) do
          info("ℹ️  No staged files found")
          0
        else
          info("📁 Found #{length(staged_files)} staged files")
          0
        end

      {_, _} ->
        info("ℹ️  Not in a git repository or no git available")
        0
    end
  end

  defp check_build_artifacts do
    info("🏗️  Checking for build artifacts...")
    issues = 0

    # Get staged files
    staged_files = get_staged_files()

    # Check for common build artifacts
    artifacts = [
      {"Rust build artifacts", ~r/target\//},
      {"Mix build artifacts", ~r/_build\//},
      {"Dependencies", ~r/deps\//},
      {"Node modules", ~r/node_modules\//},
      {"Compiled libraries", ~r/\.(so|dll|dylib)$/},
      {"IDE files", ~r/\.(vscode|idea)\//},
      {"OS files", ~r/\.(DS_Store|swp|swo)$/},
      {"Log files", ~r/\.log$/},
      {"Temporary files", ~r/\.(tmp|temp|bak|backup)$/}
    ]

    for {name, pattern} <- artifacts do
      matches = Enum.filter(staged_files, &Regex.match?(pattern, &1))

      if not Enum.empty?(matches) do
        error("❌ #{name} found in staged files:")

        for file <- matches do
          error("   #{file}")
        end

        issues + length(matches)
      else
        issues
      end
    end
  end

  defp check_large_files do
    info("📏 Checking for large files...")
    issues = 0
    # 10MB
    large_file_limit = 10 * 1024 * 1024

    staged_files = get_staged_files()

    for file <- staged_files do
      if File.exists?(file) do
        case File.stat(file) do
          {:ok, %{size: size}} when size > large_file_limit ->
            size_mb = Float.round(size / (1024 * 1024), 2)
            error("❌ Large file found: #{file} (#{size_mb}MB)")
            issues + 1

          _ ->
            issues
        end
      else
        issues
      end
    end
  end

  defp check_file_permissions do
    info("🔒 Checking file permissions...")
    issues = 0

    staged_files = get_staged_files()

    for file <- staged_files do
      if File.exists?(file) do
        # Check for executable scripts
        if String.match?(file, ~r/\.(sh|py|rb|pl)$/) do
          case File.stat(file) do
            {:ok, %{mode: mode}} ->
              # Check if file is executable (has execute bit set)
              if band(mode, 0o111) == 0 do
                error("⚠️  Script file '#{file}' is not executable")
                issues + 1
              else
                issues
              end

            _ ->
              issues
          end
        else
          issues
        end
      else
        issues
      end
    end
  end

  defp check_secrets do
    info("🔐 Checking for potential secrets...")
    issues = 0

    staged_files = get_staged_files()

    # Patterns that might indicate secrets
    secret_patterns = [
      {~r/\.env$/i, "Environment files"},
      {~r/_key$/i, "Key files"},
      {~r/_secret$/i, "Secret files"},
      {~r/api[_-]?key/i, "API key references"},
      {~r/webhook/i, "Webhook files"},
      {~r/stripe_/i, "Stripe configuration"},
      {~r/password/i, "Password references"}
    ]

    for file <- staged_files do
      # Skip example and template files
      unless String.contains?(file, "example") or String.contains?(file, "template") do
        for {pattern, description} <- secret_patterns do
          if Regex.match?(pattern, file) do
            error("⚠️  Potential secret file (#{description}): #{file}")
            issues + 1
          end
        end

        # Check file contents for secret patterns (only for small text files)
        if File.exists?(file) and File.regular?(file) do
          case File.stat(file) do
            {:ok, %{size: size}} when size < 100_000 ->
              check_file_content_for_secrets(file, issues)

            _ ->
              issues
          end
        else
          issues
        end
      end
    end
  end

  defp check_file_content_for_secrets(file, issues) do
    case File.read(file) do
      {:ok, content} ->
        # Check for common secret patterns
        secret_content_patterns = [
          {~r/sk_[a-zA-Z0-9]{20,}/, "Stripe secret key"},
          {~r/pk_[a-zA-Z0-9]{20,}/, "Stripe publishable key"},
          {~r/rk_[a-zA-Z0-9]{20,}/, "Stripe restricted key"},
          {~r/[A-Za-z0-9]{32,}/, "Long alphanumeric string (potential token)"}
        ]

        for {pattern, description} <- secret_content_patterns do
          if Regex.match?(pattern, content) do
            # Additional check to reduce false positives
            if has_secret_context?(content) do
              error("⚠️  File '#{file}' may contain #{description}")
              issues + 1
            else
              issues
            end
          else
            issues
          end
        end

      _ ->
        issues
    end
  end

  defp has_secret_context?(content) do
    # Check if the content has context that suggests it contains secrets
    secret_contexts = [
      ~r/api[_-]?key/i,
      ~r/secret/i,
      ~r/token/i,
      ~r/password/i,
      ~r/stripe/i
    ]

    Enum.any?(secret_contexts, &Regex.match?(&1, content))
  end

  defp check_elixir_formatting(auto_fix) do
    info("💅 Checking Elixir code formatting...")

    staged_elixir_files =
      get_staged_files()
      |> Enum.filter(&String.match?(&1, ~r/\.exs?$/))

    if Enum.empty?(staged_elixir_files) do
      info("ℹ️  No Elixir files to check")
      0
    else
      if auto_fix do
        info("🔧 Auto-fixing Elixir formatting...")

        case System.cmd("mix", ["format"] ++ staged_elixir_files, stderr_to_stdout: true) do
          {_, 0} ->
            info("✅ Elixir code formatted successfully")
            0

          {output, _} ->
            error("❌ Failed to format Elixir code:")
            error(output)
            1
        end
      else
        case System.cmd("mix", ["format", "--check-formatted"] ++ staged_elixir_files,
               stderr_to_stdout: true
             ) do
          {_, 0} ->
            info("✅ Elixir code formatting looks good")
            0

          {_, _} ->
            error("❌ Some Elixir files are not properly formatted")
            error("   Run 'mix format' or 'mix precommit --fix' to fix")
            1
        end
      end
    end
  end

  defp check_credo do
    info("🔍 Running Credo static analysis...")

    staged_elixir_files =
      get_staged_files()
      |> Enum.filter(&String.match?(&1, ~r/\.exs?$/))

    if Enum.empty?(staged_elixir_files) do
      info("ℹ️  No Elixir files to analyze")
      0
    else
      # Check if credo is available
      case System.cmd("mix", ["help", "credo"], stderr_to_stdout: true) do
        {_, 0} ->
          case System.cmd("mix", ["credo", "--strict"] ++ staged_elixir_files,
                 stderr_to_stdout: true
               ) do
            {_, 0} ->
              info("✅ Credo static analysis passed")
              0

            {output, _} ->
              error("⚠️  Credo found some issues:")
              info(output)
              error("   Consider fixing these issues before committing")
              1
          end

        {_, _} ->
          info("ℹ️  Credo not available - skipping static analysis")
          0
      end
    end
  end

  defp get_staged_files do
    case System.cmd("git", ["diff", "--cached", "--name-only"], stderr_to_stdout: true) do
      {output, 0} ->
        String.split(output, "\n", trim: true)

      {_, _} ->
        []
    end
  end

  defp print_summary(issues_found) do
    info("")
    info("📋 Pre-commit check summary:")

    if issues_found == 0 do
      info("✅ All checks passed!")
      info("")
      info("Safe to commit ✨")
    else
      error("❌ #{issues_found} issue(s) found that should be addressed before committing")
      info("")
      info("To fix common issues:")
      info("  • Run 'mix clean.artifacts' to remove build artifacts")
      info("  • Run 'mix format' to format Elixir code")
      info("  • Review and remove any accidentally staged files")
      info("  • Check .gitignore to prevent future issues")
      info("")
      info("To commit anyway (not recommended):")
      info("  mix precommit --force")
      info("  git commit --no-verify")
    end
  end
end
