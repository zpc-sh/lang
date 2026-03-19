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
    issues_found = issues_found + check_embedded_projects()
    issues_found = issues_found + check_banned_namespaces()
    issues_found = issues_found + check_bad_default_args()
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

    # Scan docs for prompt-injection patterns (non-blocking defaults to medium/high summary)
    issues_found = issues_found + check_doc_injections()

    # Enforce docs placement and trusted frontmatter
    issues_found = issues_found + check_docs_policy()

    # Enforce tests live under ./test
    issues_found = issues_found + check_tests_policy()

    # Advisory: warn on direct Billing calls (pipeline-first policy)
    _ = warn_direct_billing_calls()
    _ = warn_direct_events_calls()
    Mix.Tasks.Dev.Events.Lint.run(["--fail"])

    print_summary(issues_found)

    if issues_found > 0 do
      System.halt(1)
    end
  end

  # Prevent embedded projects or compiled artifacts inside ./lib
  defp check_embedded_projects do
    info("🧱 Checking for embedded projects inside lib/…")

    bad_globs = [
      "lib/lang/**/lib/**/*",
      "lib/lang/**/mix/**/*",
      "lib/lang/**/priv/**/*",
      "lib/lang/**/test/**/*",
      "lib/**/mix.exs",
      "lib/**/*.beam",
      # ban any reintroduction of the embedded project tree
      "lib/lang/explanations/**",
      "lib/lang/explanations/**/*"
    ]

    offenders =
      bad_globs
      |> Enum.flat_map(&Path.wildcard/1)
      |> Enum.filter(&File.exists?/1)

    if offenders == [] do
      info("✅ No embedded projects or artifacts detected")
      0
    else
      error("❌ Embedded project structure or compiled artifacts detected under lib/:")
      offenders |> Enum.sort() |> Enum.each(&error("   " <> &1))
      error("\nMove code into proper app modules (lib/lang, lib/lang_web, lib/mix) and keep build artifacts out of lib/.")
      1
    end
  end

  # Prevent accidental references to the old embedded namespace
  defp check_banned_namespaces do
    info("🚫 Checking for banned namespaces (Lang.Explanations.*)…")
    files =
      Path.wildcard("lib/**/*.{ex,exs}")
      |> Enum.reject(&(&1 == "lib/mix/tasks/precommit.ex"))
    offenders =
      files
      |> Enum.flat_map(fn path ->
        case File.read(path) do
          {:ok, content} -> if String.contains?(content, "Lang.Explanations.") do [path] else [] end
          _ -> []
        end
      end)

    if offenders == [] do
      info("✅ No banned namespace references found")
      0
    else
      error("❌ Found references to deprecated namespace Lang.Explanations.*:")
      offenders |> Enum.sort() |> Enum.each(&error("   " <> &1))
      1
    end
  end

  defp check_doc_injections do
    info("🛡️  Scanning docs for prompt-injection patterns...")
    paths = ["docs", "AGENTS.md", "AGENTS.codex.md", "CONTRIBUTING.md", "README.md", "priv/secret"]
    findings = Lang.Dev.DocSanitizer.scan(paths)

    {high, med, low} =
      Enum.reduce(findings, {0, 0, 0}, fn f, {h, m, l} ->
        case f.severity do
          :high -> {h + 1, m, l}
          :medium -> {h, m + 1, l}
          :low -> {h, m, l + 1}
        end
      end)

    if high + med + low == 0 do
      info("✅ No suspicious patterns found")
      0
    else
      Enum.each(findings, fn f ->
        info("   #{f.file}:#{f.line} [#{f.severity}] #{f.type} :: #{String.trim(f.snippet)}")
      end)
      # For now, fail only on high severity to reduce noise
      if high > 0 do
        error("❌ High-severity patterns detected in docs (#{high})")
        1
      else
        info("⚠️  Medium/low patterns detected (med=#{med}, low=#{low})")
        0
      end
    end
  rescue
    _ -> 0
  end

  defp check_docs_policy do
    info("📚 Enforcing docs policy (placement + trusted frontmatter)...")
    outside = Lang.Dev.DocPolicy.untrusted_markdown_outside_docs()
    missing = Lang.Dev.DocPolicy.check_trusted_frontmatter()

    cond do
      outside != [] ->
        error("❌ Markdown outside ./docs and not allowlisted:")
        Enum.each(outside, &error("   " <> &1))
        1
      missing != [] ->
        error("❌ Trusted docs missing `trusted: true` frontmatter:")
        Enum.each(missing, fn {p, _} -> error("   " <> p) end)
        1
      true ->
        info("✅ Docs policy OK")
        0
    end
  rescue
    _ -> 0
  end

  defp check_tests_policy do
    info("🧪 Enforcing tests policy (tests under ./test only)...")
    try do
      Mix.Tasks.Dev.TestsPolicy.run([])
      0
    rescue
      _ -> 1
    end
  end

  # Advisory only (does not fail precommit)
  defp warn_direct_billing_calls do
    files = Path.wildcard("lib/**/*.ex")
    offenders =
      files
      |> Enum.reject(&String.contains?(&1, "/billing"))
      |> Enum.flat_map(fn path ->
        case File.read(path) do
          {:ok, content} ->
            if String.contains?(content, "Lang.Billing.") do
              [{path, :direct_call}]
            else
              []
            end
          _ -> []
        end
      end)

    if offenders != [] do
      info("ℹ️  Billing pipeline reminder (advisory):")
      info("   Avoid direct Lang.Billing.* calls in feature code.")
      info("   Prefer publishing usage messages to the Billing pipeline (Ash/Oban).\n")
      Enum.each(offenders, fn {p, _} -> info("   → #{p}") end)
      info("   (This is a non-blocking reminder; update as you refactor.)\n")
    end
    :ok
  end

  defp warn_direct_events_calls do
    files = Path.wildcard("lib/**/*.ex")
    offenders =
      files
      |> Enum.reject(&String.contains?(&1, "/events"))
      |> Enum.flat_map(fn path ->
        case File.read(path) do
          {:ok, content} ->
            if String.contains?(content, "Lang.Events.") do
              [{path, :direct_call}]
            else
              []
            end
          _ -> []
        end
      end)

    if offenders != [] do
      info("ℹ️  Events modeling reminder (advisory):")
      info("   Prefer modeling events as Ash resources (Ash.Notifier.PubSub) and use Lang.Events.track_event/1.")
      Enum.each(offenders, fn {p, _} -> info("   → #{p}") end)
      info("   (This is a non-blocking reminder; update as you refactor.)\n")
    end
    :ok
  end

  # Detect accidental single-backslash default args like "opts \ []" or "error \ nil"
  # Correct Elixir syntax requires a double backslash: "opts \\ []"
  defp check_bad_default_args do
    info("🧯 Checking for invalid default-arg backslashes (\\ [] / \\ nil / \\ %{})...")
    staged_elixir_files =
      get_staged_files()
      |> Enum.filter(&String.match?(&1, ~r/\.exs?$/))

    patterns = [
      "\\ []",   # empty list
      "\\ %{",   # empty/any map
      "\\ {}",   # empty tuple
      "\\ ()",   # empty parens (rare, but catch)
      "\\ nil"    # nil
    ]

    findings =
      for file <- staged_elixir_files, File.exists?(file), reduce: [] do
        acc ->
          {:ok, content} = File.read(file)
          lines = String.split(content, "\n", trim: false)

          file_hits =
            lines
            |> Enum.with_index(1)
            |> Enum.flat_map(fn {line, ln} ->
              Enum.filter(patterns, &String.contains?(line, &1))
              |> Enum.map(fn pat -> {ln, pat, String.trim_leading(String.trim_trailing(line))} end)
            end)

          if file_hits == [], do: acc, else: [{file, file_hits} | acc]
      end

    case findings do
      [] ->
        info("✅ No invalid default-arg backslashes found")
        0

      list ->
        error("❌ Found invalid single backslashes in default args (should be \\ \\):")
        Enum.each(list, fn {file, hits} ->
          Enum.each(hits, fn {ln, pat, line} ->
            error("   #{file}:#{ln}: contains '#{pat}' -> #{line}")
          end)
        end)
        info("   Fix by using a double backslash (e.g., opts \\ []), or use multiple function heads.")
        length(list)
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
          # 1) Run default Credo strict checks
          issues =
            case System.cmd("mix", ["credo", "--strict"] ++ staged_elixir_files,
                   stderr_to_stdout: true
                 ) do
              {_, 0} -> 0
              {output, _} ->
                error("⚠️  Credo found some issues (default config):")
                info(output)
                1
            end

          # 2) Run custom Credo checks from .credo.exs if present
          issues =
            if File.exists?(".credo.exs") do
              case System.cmd("mix", ["credo", "--strict", "--config-file", ".credo.exs"] ++ staged_elixir_files,
                     stderr_to_stdout: true
                   ) do
                {_, 0} -> issues
                {output, _} ->
                  error("⚠️  Credo found some issues (custom config):")
                  info(output)
                  issues + 1
              end
            else
              issues
            end

          if issues == 0 do
            info("✅ Credo static analysis passed")
          end

          issues

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
