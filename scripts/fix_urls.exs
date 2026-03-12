#!/usr/bin/env elixir

defmodule URLFixer do
  @moduledoc """
  URL Standardization Script for LANG Platform

  Fixes critical URL issues:
  1. Replace fake 'lang.nocsi.com' with correct 'lang.nocsi.com'
  2. Replace localhost URLs with production URLs
  3. Standardize all API endpoints to use correct domain

  Usage:
    mix run scripts/fix_urls.exs
    mix run scripts/fix_urls.exs --dry-run
    mix run scripts/fix_urls.exs --verbose
  """

  @correct_domain "lang.nocsi.com"
  @fake_domains ["lang.nocsi.com", "lang.nocsi.com"]
  @localhost_patterns [
    "https://lang.nocsi.com",
    "https://lang.nocsi.com",
    "https://lang.nocsi.com",
    "https://lang.nocsi.com"
  ]

  def run(args \\ []) do
    IO.puts("\n🔧 LANG URL Standardization Script")
    IO.puts("=" |> String.duplicate(60))
    IO.puts("✅ Correct domain: #{@correct_domain}")
    IO.puts("❌ Fixing fake domains: #{Enum.join(@fake_domains, ", ")}")
    IO.puts("🏠 Fixing localhost URLs")

    dry_run = "--dry-run" in args
    verbose = "--verbose" in args

    if dry_run do
      IO.puts("\n🔍 DRY RUN MODE - No files will be modified")
    end

    results = %{
      files_processed: 0,
      fake_domain_fixes: 0,
      localhost_fixes: 0,
      total_fixes: 0,
      files_changed: []
    }

    # Find all files that might contain URLs
    files = find_target_files()

    IO.puts("\nFound #{length(files)} files to process")

    # Process each file
    results =
      Enum.reduce(files, results, fn file, acc ->
        process_file(file, acc, dry_run, verbose)
      end)

    # Generate summary report
    generate_report(results, dry_run)
  end

  defp find_target_files do
    [
      # Documentation files
      Path.wildcard("**/*.md"),
      # Template files
      Path.wildcard("lib/lang_web/**/*.heex"),
      # Elixir source files with URLs
      Path.wildcard("lib/**/*.ex"),
      Path.wildcard("lib/**/*.exs"),
      # Config files
      Path.wildcard("config/**/*.exs"),
      # Scripts
      Path.wildcard("scripts/**/*.exs")
    ]
    |> List.flatten()
    |> Enum.filter(&File.exists?/1)
    |> Enum.filter(fn file ->
      # Skip certain files
      !String.contains?(file, [".git/", "_build/", "deps/", "node_modules/"])
    end)
    |> Enum.uniq()
  end

  defp process_file(file_path, results, dry_run, verbose) do
    content = File.read!(file_path)
    original_content = content

    if verbose do
      IO.puts("  📄 Processing: #{file_path}")
    end

    # Apply all URL fixes
    {new_content, file_fixes} = apply_url_fixes(content, file_path)

    # Count the fixes
    fake_fixes = file_fixes.fake_domain_fixes
    localhost_fixes = file_fixes.localhost_fixes
    total_file_fixes = fake_fixes + localhost_fixes

    # Update results
    results = %{
      results
      | files_processed: results.files_processed + 1,
        fake_domain_fixes: results.fake_domain_fixes + fake_fixes,
        localhost_fixes: results.localhost_fixes + localhost_fixes,
        total_fixes: results.total_fixes + total_file_fixes
    }

    # Write file if changes were made and not dry run
    if new_content != original_content do
      if verbose do
        IO.puts("    ✅ Fixed #{total_file_fixes} URLs")
      end

      updated_results = %{
        results
        | files_changed: [%{file: file_path, fixes: total_file_fixes} | results.files_changed]
      }

      unless dry_run do
        File.write!(file_path, new_content)
      end

      updated_results
    else
      results
    end
  end

  defp apply_url_fixes(content, file_path) do
    fixes = %{fake_domain_fixes: 0, localhost_fixes: 0}

    # Fix 1: Replace fake domains
    {content, fixes} = fix_fake_domains(content, fixes)

    # Fix 2: Replace localhost URLs
    {content, fixes} = fix_localhost_urls(content, fixes, file_path)

    {content, fixes}
  end

  defp fix_fake_domains(content, fixes) do
    Enum.reduce(@fake_domains, {content, fixes}, fn fake_domain, {acc_content, acc_fixes} ->
      # Count occurrences before replacement
      count = length(Regex.scan(~r/#{Regex.escape(fake_domain)}/, acc_content))

      # Replace the domain
      new_content = String.replace(acc_content, fake_domain, @correct_domain)

      new_fixes = %{acc_fixes | fake_domain_fixes: acc_fixes.fake_domain_fixes + count}
      {new_content, new_fixes}
    end)
  end

  defp fix_localhost_urls(content, fixes, file_path) do
    Enum.reduce(@localhost_patterns, {content, fixes}, fn localhost_url,
                                                          {acc_content, acc_fixes} ->
      # Determine the correct replacement based on file context
      replacement = determine_localhost_replacement(localhost_url, file_path)

      # Count occurrences
      count = length(Regex.scan(~r/#{Regex.escape(localhost_url)}/, acc_content))

      # Replace
      new_content = String.replace(acc_content, localhost_url, replacement)

      new_fixes = %{acc_fixes | localhost_fixes: acc_fixes.localhost_fixes + count}
      {new_content, new_fixes}
    end)
  end

  defp determine_localhost_replacement(localhost_url, file_path) do
    cond do
      # Development documentation should keep localhost for local testing examples
      String.contains?(file_path, ["development", "local", "dev"]) ->
        localhost_url

      # API documentation should use production domain
      String.contains?(file_path, ["api", "docs"]) ->
        String.replace(localhost_url, ~r/https?:\/\/localhost:\d+/, "https://#{@correct_domain}")

      # README and main docs should use production domain
      String.contains?(file_path, ["README", "DEPLOYMENT", "priv/docs"]) ->
        String.replace(localhost_url, ~r/https?:\/\/localhost:\d+/, "https://#{@correct_domain}")

      # Default to production domain
      true ->
        String.replace(localhost_url, ~r/https?:\/\/localhost:\d+/, "https://#{@correct_domain}")
    end
  end

  defp generate_report(results, dry_run) do
    IO.puts(("\n" <> "=") |> String.duplicate(60))
    IO.puts("📊 URL STANDARDIZATION REPORT")
    IO.puts("=" |> String.duplicate(60))

    IO.puts("\n📈 SUMMARY")
    IO.puts("Files processed: #{results.files_processed}")
    IO.puts("Files modified: #{length(results.files_changed)}")
    IO.puts("Fake domain fixes: #{results.fake_domain_fixes}")
    IO.puts("Localhost fixes: #{results.localhost_fixes}")
    IO.puts("Total URL fixes: #{results.total_fixes}")

    if length(results.files_changed) > 0 do
      IO.puts("\n📝 MODIFIED FILES")

      results.files_changed
      |> Enum.reverse()
      |> Enum.each(fn %{file: file, fixes: fixes} ->
        IO.puts("  ✅ #{file} (#{fixes} fixes)")
      end)
    end

    if dry_run do
      IO.puts("\n🔍 DRY RUN COMPLETE")
      IO.puts("Run without --dry-run to apply these fixes")
    else
      IO.puts("\n✅ URL STANDARDIZATION COMPLETE")
    end

    if results.total_fixes > 0 do
      IO.puts("\n💡 RECOMMENDATIONS")
      IO.puts("1. Test the application to ensure all URLs are working")
      IO.puts("2. Update any CI/CD scripts that might reference old URLs")
      IO.puts("3. Consider adding URL validation to prevent future issues")
      IO.puts("4. Run the link audit script to verify all fixes")
    end

    if results.total_fixes == 0 do
      IO.puts("🎉 No URL fixes needed - all URLs are already correct!")
    end

    results
  end
end

# Run if called directly
if length(System.argv()) > 0 or !IEx.started?() do
  URLFixer.run(System.argv())
end
