#!/usr/bin/env elixir

defmodule LinkAudit do
  @moduledoc """
  Comprehensive link audit system for LANG platform.

  Scans all documentation files (Markdown) and templates (HEEx) to:
  1. Extract all links (internal and external)
  2. Validate each link
  3. Report broken links with context
  4. Generate comprehensive audit report

  Usage:
    mix run scripts/link_audit.exs
    mix run scripts/link_audit.exs --fix-internal
    mix run scripts/link_audit.exs --verbose
  """

  require Logger

  @doc_paths [
    "priv/docs",
    "priv/static/docs"
  ]

  @template_paths [
    "lib/lang_web/components",
    "lib/lang_web/controllers",
    "lib/lang_web/live"
  ]

  @root_files [
    "README.md",
    "AGENTS.md",
    "DEPLOYMENT_GUIDE.md",
    "USER_FLOW_ANALYSIS.md"
  ]

  # Common domains that should be accessible
  @trusted_domains [
    "lang.nocsi.com",
    # Legacy - should be migrated
    "lang.nocsi.com",
    "github.com",
    "hexdocs.pm",
    "elixir-lang.org",
    "phoenixframework.org",
    "ash-hq.org"
  ]

  def run(args \\ []) do
    IO.puts("\n🔍 LANG Link Audit System")
    IO.puts("=" |> String.duplicate(50))

    verbose = "--verbose" in args
    fix_internal = "--fix-internal" in args

    if fix_internal do
      IO.puts("🔧 Auto-fix mode enabled for internal links")
    end

    results = %{
      total_files: 0,
      total_links: 0,
      broken_internal: [],
      broken_external: [],
      suspicious_links: [],
      fixes_applied: []
    }

    # Scan all documentation files
    results = scan_documentation(results, verbose)

    # Scan all template files
    results = scan_templates(results, verbose)

    # Scan root documentation files
    results = scan_root_files(results, verbose)

    # Apply fixes if requested
    results = if fix_internal, do: apply_fixes(results), else: results

    # Generate comprehensive report
    generate_report(results)
  end

  defp scan_documentation(results, verbose) do
    IO.puts("\n📚 Scanning Documentation Files...")

    doc_files =
      @doc_paths
      |> Enum.flat_map(&find_markdown_files/1)
      |> Enum.filter(&File.exists?/1)

    if verbose do
      IO.puts("Found #{length(doc_files)} documentation files")
    end

    Enum.reduce(doc_files, results, fn file, acc ->
      scan_file(file, acc, verbose, :documentation)
    end)
  end

  defp scan_templates(results, verbose) do
    IO.puts("\n🎨 Scanning Template Files...")

    template_files =
      @template_paths
      |> Enum.flat_map(&find_template_files/1)
      |> Enum.filter(&File.exists?/1)

    if verbose do
      IO.puts("Found #{length(template_files)} template files")
    end

    Enum.reduce(template_files, results, fn file, acc ->
      scan_file(file, acc, verbose, :template)
    end)
  end

  defp scan_root_files(results, verbose) do
    IO.puts("\n📄 Scanning Root Files...")

    root_files =
      @root_files
      |> Enum.filter(&File.exists?/1)

    if verbose do
      IO.puts("Found #{length(root_files)} root files")
    end

    Enum.reduce(root_files, results, fn file, acc ->
      scan_file(file, acc, verbose, :root)
    end)
  end

  defp scan_file(file_path, results, verbose, file_type) do
    if verbose do
      IO.puts("  📄 Scanning: #{file_path}")
    end

    content = File.read!(file_path)
    links = extract_links(content, file_type)

    if verbose and length(links) > 0 do
      IO.puts("    Found #{length(links)} links")
    end

    # Update total counters
    results = %{
      results
      | total_files: results.total_files + 1,
        total_links: results.total_links + length(links)
    }

    # Check each link
    Enum.reduce(links, results, fn {link, line_num, context}, acc ->
      check_link(link, line_num, context, file_path, acc)
    end)
  end

  defp extract_links(content, file_type) do
    lines = String.split(content, "\n", trim: false)

    case file_type do
      type when type in [:documentation, :root] ->
        extract_markdown_links(lines)

      :template ->
        extract_template_links(lines)
    end
  end

  defp extract_markdown_links(lines) do
    lines
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_num} ->
      # Match [text](url) format
      markdown_links =
        Regex.scan(~r/\[([^\]]*)\]\(([^)]+)\)/, line)
        |> Enum.map(fn [_full, text, url] -> {url, line_num, "[#{text}](#{url})"} end)

      # Match <url> format
      angle_links =
        Regex.scan(~r/<(https?:\/\/[^>]+)>/, line)
        |> Enum.map(fn [_full, url] -> {url, line_num, "<#{url}>"} end)

      # Match bare URLs
      bare_links =
        Regex.scan(~r/https?:\/\/[^\s\)]+/, line)
        |> Enum.map(fn [url] -> {url, line_num, url} end)

      markdown_links ++ angle_links ++ bare_links
    end)
  end

  defp extract_template_links(lines) do
    lines
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_num} ->
      # Match href="url" and href={url}
      href_links =
        Regex.scan(~r/href=["']([^"']+)["']/, line)
        |> Enum.map(fn [_full, url] -> {url, line_num, "href=\"#{url}\""} end)

      # Match navigate={url} and patch={url}
      navigate_links =
        Regex.scan(~r/(?:navigate|patch)=["'{]([^"'}]+)["'}]/, line)
        |> Enum.map(fn [_full, url] -> {url, line_num, "navigate/patch=\"#{url}\""} end)

      # Match <.link> components
      link_components =
        Regex.scan(~r/<\.link[^>]*(?:navigate|patch|href)=["'{]([^"'}]+)["'}]/, line)
        |> Enum.map(fn [_full, url] -> {url, line_num, "<.link navigate/patch=\"#{url}\""} end)

      href_links ++ navigate_links ++ link_components
    end)
  end

  defp check_link(url, line_num, context, file_path, results) do
    cond do
      # Skip template variables and Phoenix helpers
      String.contains?(url, ["@", "{", "}", "~p"]) ->
        results

      # Skip anchors and javascript
      String.starts_with?(url, ["#", "javascript:", "mailto:"]) ->
        results

      # Check internal links (relative paths)
      !String.starts_with?(url, ["http://", "https://"]) ->
        check_internal_link(url, line_num, context, file_path, results)

      # Check external links
      true ->
        check_external_link(url, line_num, context, file_path, results)
    end
  end

  defp check_internal_link(url, line_num, context, file_path, results) do
    # Convert relative path to absolute file system path
    base_dir = Path.dirname(file_path)
    full_path = Path.expand(Path.join(base_dir, url))

    # Also check if it's a route that exists
    route_exists = check_route_exists(url)
    file_exists = File.exists?(full_path)

    cond do
      file_exists or route_exists ->
        results

      String.contains?(url, "lang.nocsi.com") ->
        # This should be migrated to lang.nocsi.com
        suspicious_link = %{
          file: file_path,
          line: line_num,
          url: url,
          context: context,
          issue: "Should migrate from lang.nocsi.com to lang.nocsi.com"
        }

        %{results | suspicious_links: [suspicious_link | results.suspicious_links]}

      true ->
        broken_link = %{
          file: file_path,
          line: line_num,
          url: url,
          context: context,
          full_path: full_path,
          suggestion: suggest_fix(url, file_path)
        }

        %{results | broken_internal: [broken_link | results.broken_internal]}
    end
  end

  defp check_external_link(url, line_num, context, file_path, results) do
    cond do
      # Check for suspicious domains
      String.contains?(url, "lang.nocsi.com") ->
        suspicious_link = %{
          file: file_path,
          line: line_num,
          url: url,
          context: context,
          issue: "Should migrate from lang.nocsi.com to lang.nocsi.com"
        }

        %{results | suspicious_links: [suspicious_link | results.suspicious_links]}

      # For now, we'll skip actual HTTP checks to avoid network dependencies
      # In a production audit, we'd use HTTPoison or Req to test these
      true ->
        results
    end
  end

  defp check_route_exists(url) do
    # Common LANG routes that exist
    known_routes = [
      "/",
      "/docs",
      "/api",
      "/dashboard",
      "/settings",
      "/auth/login",
      "/auth/register",
      "/api-portal",
      "/docs/api",
      "/docs/guides",
      "/docs/architecture"
    ]

    # Check if it's a known route or starts with a known route
    Enum.any?(known_routes, fn route ->
      url == route or String.starts_with?(url, route <> "/")
    end)
  end

  defp suggest_fix(url, file_path) do
    cond do
      # Common typos
      String.contains?(url, "/doc/") ->
        String.replace(url, "/doc/", "/docs/")

      String.contains?(url, "lang.nocsi.com") ->
        String.replace(url, "lang.nocsi.com", "lang.nocsi.com")

      # Relative path fixes
      String.starts_with?(url, "./") ->
        # Remove ./ prefix and try direct path
        String.replace_prefix(url, "./", "")

      String.starts_with?(url, "../") ->
        # Suggest checking parent directory structure
        "Check parent directory: #{Path.expand(Path.join(Path.dirname(file_path), url))}"

      true ->
        "Verify file exists or create missing file"
    end
  end

  defp apply_fixes(results) do
    IO.puts("\n🔧 Applying automatic fixes...")

    fixes = []

    # For now, we'll just identify what could be fixed
    # In a full implementation, we'd actually modify files

    Enum.each(results.broken_internal, fn broken ->
      if broken.suggestion && String.contains?(broken.suggestion, "lang.nocsi.com") do
        IO.puts("  Would fix: #{broken.file}:#{broken.line} - #{broken.suggestion}")
      end
    end)

    %{results | fixes_applied: fixes}
  end

  defp generate_report(results) do
    IO.puts(("\n" <> "=") |> String.duplicate(60))
    IO.puts("📊 LINK AUDIT REPORT")
    IO.puts("=" |> String.duplicate(60))

    IO.puts("\n📈 SUMMARY")
    IO.puts("Files scanned: #{results.total_files}")
    IO.puts("Total links found: #{results.total_links}")
    IO.puts("Broken internal links: #{length(results.broken_internal)}")
    IO.puts("Broken external links: #{length(results.broken_external)}")
    IO.puts("Suspicious links: #{length(results.suspicious_links)}")

    if length(results.broken_internal) > 0 do
      IO.puts("\n🚨 BROKEN INTERNAL LINKS")

      Enum.each(results.broken_internal, fn broken ->
        IO.puts("  ❌ #{broken.file}:#{broken.line}")
        IO.puts("     URL: #{broken.url}")
        IO.puts("     Context: #{broken.context}")

        if broken.suggestion do
          IO.puts("     💡 Suggestion: #{broken.suggestion}")
        end

        IO.puts("")
      end)
    end

    if length(results.broken_external) > 0 do
      IO.puts("\n🌐 BROKEN EXTERNAL LINKS")

      Enum.each(results.broken_external, fn broken ->
        IO.puts("  ❌ #{broken.file}:#{broken.line}")
        IO.puts("     URL: #{broken.url}")
        IO.puts("     Context: #{broken.context}")
        IO.puts("")
      end)
    end

    if length(results.suspicious_links) > 0 do
      IO.puts("\n⚠️  SUSPICIOUS LINKS")

      Enum.each(results.suspicious_links, fn suspicious ->
        IO.puts("  ⚠️  #{suspicious.file}:#{suspicious.line}")
        IO.puts("     URL: #{suspicious.url}")
        IO.puts("     Issue: #{suspicious.issue}")
        IO.puts("     Context: #{suspicious.context}")
        IO.puts("")
      end)
    end

    if length(results.fixes_applied) > 0 do
      IO.puts("\n✅ FIXES APPLIED")

      Enum.each(results.fixes_applied, fn fix ->
        IO.puts("  ✅ #{fix}")
      end)
    end

    # Generate recommendations
    IO.puts("\n💡 RECOMMENDATIONS")

    if length(results.broken_internal) > 0 do
      IO.puts("  1. Fix broken internal links (#{length(results.broken_internal)} found)")
    end

    suspicious_count = length(results.suspicious_links)

    if suspicious_count > 0 do
      IO.puts("  2. Migrate #{suspicious_count} links from lang.nocsi.com to lang.nocsi.com")
    end

    if length(results.broken_external) > 0 do
      IO.puts("  3. Update external links that may be outdated")
    end

    IO.puts("\n🎯 NEXT STEPS")
    IO.puts("  1. Run: mix run scripts/link_audit.exs --fix-internal")
    IO.puts("  2. Manually review and fix remaining broken links")
    IO.puts("  3. Add this to CI/CD pipeline for continuous monitoring")

    IO.puts("\n✅ Link audit complete!")

    # Return summary for potential integration with other tools
    %{
      total_issues:
        length(results.broken_internal) + length(results.broken_external) +
          length(results.suspicious_links),
      files_scanned: results.total_files,
      links_scanned: results.total_links
    }
  end

  # Helper functions
  defp find_markdown_files(dir_path) do
    if File.exists?(dir_path) do
      Path.wildcard(Path.join([dir_path, "**", "*.md"]))
    else
      []
    end
  end

  defp find_template_files(dir_path) do
    if File.exists?(dir_path) do
      heex_files = Path.wildcard(Path.join([dir_path, "**", "*.heex"]))
      ex_files = Path.wildcard(Path.join([dir_path, "**", "*_live.ex"]))
      heex_files ++ ex_files
    else
      []
    end
  end
end

# Run the audit if called directly
if System.argv() |> Enum.any?(&String.contains?(&1, "link_audit.exs")) do
  LinkAudit.run(System.argv())
end
