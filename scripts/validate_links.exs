#!/usr/bin/env elixir

defmodule LinkValidator do
  @moduledoc """
  Comprehensive link validation script for LANG platform.

  Validates all internal links to ensure they point to existing files or routes.
  Reports broken links with suggestions for fixes.

  Usage:
    mix run scripts/validate_links.exs
    mix run scripts/validate_links.exs --verbose
    mix run scripts/validate_links.exs --fix-suggestions
  """

  require Logger

  @known_routes [
    "/",
    "/docs",
    "/api",
    "/dashboard",
    "/settings",
    "/auth",
    "/auth/login",
    "/auth/register",
    "/auth/logout",
    "/api-portal",
    "/health",
    "/docs/api",
    "/docs/guides",
    "/docs/architecture",
    "/docs/tutorials",
    "/docs/text",
    "/docs/filesystem",
    "/docs/cloud",
    "/docs/systems",
    "/privacy",
    "/terms",
    "/contact",
    "/community",
    "/sign-up",
    "/analyze"
  ]

  @valid_file_extensions [
    ".md",
    ".html",
    ".heex",
    ".ex",
    ".exs",
    ".txt",
    ".json",
    ".css",
    ".js",
    ".png",
    ".jpg",
    ".jpeg",
    ".svg",
    ".ico"
  ]

  def run(args \\ []) do
    IO.puts("\n🔗 LANG Link Validation System")
    IO.puts("=" |> String.duplicate(50))

    verbose = "--verbose" in args
    show_suggestions = "--fix-suggestions" in args

    results = %{
      total_files: 0,
      total_links: 0,
      valid_links: 0,
      broken_links: [],
      route_links: 0,
      file_links: 0,
      anchor_links: 0,
      external_links: 0
    }

    # Find and scan all relevant files
    files = find_documentation_files()

    if verbose do
      IO.puts("Found #{length(files)} files to validate")
    end

    # Process each file
    results =
      Enum.reduce(files, results, fn file, acc ->
        validate_file(file, acc, verbose)
      end)

    # Generate comprehensive report
    generate_validation_report(results, show_suggestions)
  end

  defp find_documentation_files do
    [
      # Documentation files
      Path.wildcard("*.md"),
      Path.wildcard("priv/docs/**/*.md"),
      Path.wildcard("priv/static/docs/**/*.md"),
      # Template files with links
      Path.wildcard("lib/lang_web/**/*.heex"),
      Path.wildcard("lib/lang_web/**/*_live.ex")
    ]
    |> List.flatten()
    |> Enum.filter(&File.exists?/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp validate_file(file_path, results, verbose) do
    if verbose do
      IO.puts("  🔍 Validating: #{file_path}")
    end

    content = File.read!(file_path)
    links = extract_internal_links(content)

    if verbose and length(links) > 0 do
      IO.puts("    Found #{length(links)} internal links")
    end

    # Update counters
    results = %{
      results
      | total_files: results.total_files + 1,
        total_links: results.total_links + length(links)
    }

    # Validate each link
    Enum.reduce(links, results, fn {link, line_num, context}, acc ->
      validate_link(link, line_num, context, file_path, acc, verbose)
    end)
  end

  defp extract_internal_links(content) do
    lines = String.split(content, "\n", trim: false)

    lines
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_num} ->
      # Extract various link formats
      markdown_links = extract_markdown_links(line, line_num)
      template_links = extract_template_links(line, line_num)

      markdown_links ++ template_links
    end)
    |> Enum.filter(fn {url, _, _} ->
      # Only internal links (not external URLs, mailto, javascript, etc.)
      is_internal_link?(url)
    end)
    |> Enum.uniq_by(fn {url, _, _} -> url end)
  end

  defp extract_markdown_links(line, line_num) do
    # Match [text](url) format
    Regex.scan(~r/\[([^\]]*)\]\(([^)]+)\)/, line)
    |> Enum.map(fn [_full, text, url] -> {url, line_num, "[#{text}](#{url})"} end)
  end

  defp extract_template_links(line, line_num) do
    patterns = [
      # href attributes
      ~r/href=["']([^"']+)["']/,
      # Phoenix navigate/patch
      ~r/(?:navigate|patch)=["'{]([^"'}]+)["'}]/,
      # <.link> components
      ~r/<\.link[^>]*(?:navigate|patch|href)=["'{]([^"'}]+)["'}]/
    ]

    Enum.flat_map(patterns, fn regex ->
      Regex.scan(regex, line)
      |> Enum.map(fn [_full, url] -> {url, line_num, "href/navigate=\"#{url}\""} end)
    end)
  end

  defp is_internal_link?(url) do
    !String.starts_with?(url, [
      "http://",
      "https://",
      "ftp://",
      "mailto:",
      "javascript:",
      "tel:",
      "#"
    ]) and !String.contains?(url, ["@", "{", "}", "~p", "<%="])
  end

  defp validate_link(url, line_num, context, file_path, results, verbose) do
    cond do
      # Check if it's a known route
      is_known_route?(url) ->
        if verbose do
          IO.puts("      ✅ Route: #{url}")
        end

        %{results | valid_links: results.valid_links + 1, route_links: results.route_links + 1}

      # Check if it's a valid file path
      is_valid_file_path?(url, file_path) ->
        if verbose do
          IO.puts("      ✅ File: #{url}")
        end

        %{results | valid_links: results.valid_links + 1, file_links: results.file_links + 1}

      # It's a broken link
      true ->
        broken_link = %{
          file: file_path,
          line: line_num,
          url: url,
          context: context,
          suggestion: suggest_fix(url, file_path),
          severity: determine_severity(url)
        }

        if verbose do
          IO.puts("      ❌ Broken: #{url}")
        end

        %{results | broken_links: [broken_link | results.broken_links]}
    end
  end

  defp is_known_route?(url) do
    # Clean the URL (remove query params, fragments)
    clean_url = url |> String.split("?") |> hd() |> String.split("#") |> hd()

    Enum.any?(@known_routes, fn route ->
      clean_url == route or String.starts_with?(clean_url, route <> "/")
    end)
  end

  defp is_valid_file_path?(url, current_file_path) do
    cond do
      # Relative path
      !String.starts_with?(url, "/") ->
        validate_relative_path(url, current_file_path)

      # Absolute path from project root
      String.starts_with?(url, "/") ->
        validate_absolute_path(url)

      true ->
        false
    end
  end

  defp validate_relative_path(url, current_file_path) do
    base_dir = Path.dirname(current_file_path)
    full_path = Path.expand(Path.join(base_dir, url))

    File.exists?(full_path) or is_valid_documentation_reference?(url, base_dir)
  end

  defp validate_absolute_path(url) do
    # Remove leading slash and check from project root
    relative_url = String.trim_leading(url, "/")
    File.exists?(relative_url) or is_docs_reference?(url)
  end

  defp is_valid_documentation_reference?(url, base_dir) do
    # Check common documentation patterns
    possible_paths = [
      Path.join(base_dir, url <> ".md"),
      Path.join(base_dir, url <> "/index.md"),
      Path.join("priv/docs", url),
      Path.join("priv/docs", url <> ".md"),
      Path.join("priv/static/docs", url),
      Path.join("priv/static/docs", url <> ".md")
    ]

    Enum.any?(possible_paths, &File.exists?/1)
  end

  defp is_docs_reference?(url) do
    # Check if it's a reference to documentation structure
    docs_patterns = [
      "docs/",
      "api/",
      "guides/",
      "tutorials/",
      "architecture/"
    ]

    Enum.any?(docs_patterns, &String.contains?(url, &1))
  end

  defp suggest_fix(url, file_path) do
    cond do
      # Common typos
      String.contains?(url, "/doc/") ->
        "Try: " <> String.replace(url, "/doc/", "/docs/")

      String.contains?(url, "/guide/") ->
        "Try: " <> String.replace(url, "/guide/", "/guides/")

      # Missing file extension
      !String.contains?(url, ".") and !String.ends_with?(url, "/") ->
        "Try: #{url}.md or #{url}/index.md"

      # Relative path issues
      String.starts_with?(url, "../") ->
        "Check parent directory structure from #{Path.dirname(file_path)}"

      String.starts_with?(url, "./") ->
        "Check current directory: #{Path.dirname(file_path)}"

      # Documentation structure
      String.contains?(url, "/docs/") ->
        "Verify documentation exists in priv/docs/ or priv/static/docs/"

      true ->
        "Verify file exists or create missing documentation"
    end
  end

  defp determine_severity(url) do
    cond do
      String.contains?(url, ["/api/", "/docs/"]) -> :high
      String.starts_with?(url, "/") -> :medium
      true -> :low
    end
  end

  defp generate_validation_report(results, show_suggestions) do
    IO.puts(("\n" <> "=") |> String.duplicate(60))
    IO.puts("📊 LINK VALIDATION REPORT")
    IO.puts("=" |> String.duplicate(60))

    IO.puts("\n📈 SUMMARY")
    IO.puts("Files validated: #{results.total_files}")
    IO.puts("Total internal links: #{results.total_links}")
    IO.puts("Valid links: #{results.valid_links}")
    IO.puts("Broken links: #{length(results.broken_links)}")
    IO.puts("Route links: #{results.route_links}")
    IO.puts("File links: #{results.file_links}")

    # Calculate health percentage
    health_percentage =
      if results.total_links > 0 do
        Float.round(results.valid_links / results.total_links * 100, 1)
      else
        100.0
      end

    IO.puts("\n🏥 LINK HEALTH: #{health_percentage}%")

    if length(results.broken_links) > 0 do
      IO.puts("\n🚨 BROKEN LINKS")

      # Group by severity
      grouped = Enum.group_by(results.broken_links, & &1.severity)

      [:high, :medium, :low]
      |> Enum.each(fn severity ->
        links = Map.get(grouped, severity, [])

        if length(links) > 0 do
          severity_icon =
            case severity do
              :high -> "🔴"
              :medium -> "🟡"
              :low -> "🟠"
            end

          IO.puts(
            "\n#{severity_icon} #{String.upcase(to_string(severity))} PRIORITY (#{length(links)} links)"
          )

          links
          # Limit output
          |> Enum.take(10)
          |> Enum.each(fn broken ->
            IO.puts("  ❌ #{broken.file}:#{broken.line}")
            IO.puts("     URL: #{broken.url}")
            IO.puts("     Context: #{broken.context}")

            if show_suggestions and broken.suggestion do
              IO.puts("     💡 Suggestion: #{broken.suggestion}")
            end

            IO.puts("")
          end)

          if length(links) > 10 do
            IO.puts("  ... and #{length(links) - 10} more #{severity} priority issues")
          end
        end
      end)
    end

    IO.puts("\n💡 RECOMMENDATIONS")

    cond do
      health_percentage >= 95 ->
        IO.puts("  🎉 Excellent link health! Minor cleanup needed.")

      health_percentage >= 80 ->
        IO.puts("  ✅ Good link health. Address high priority issues.")

      health_percentage >= 60 ->
        IO.puts("  ⚠️  Moderate issues. Focus on broken documentation links.")

      true ->
        IO.puts("  🚨 Critical link health issues. Immediate attention needed.")
    end

    if length(results.broken_links) > 0 do
      high_priority =
        length(Map.get(Enum.group_by(results.broken_links, & &1.severity), :high, []))

      if high_priority > 0 do
        IO.puts("  1. Fix #{high_priority} high-priority broken links first")
      end

      IO.puts("  2. Verify documentation structure in priv/docs/")
      IO.puts("  3. Check file paths are relative to correct directories")
      IO.puts("  4. Consider adding automated link checking to CI/CD")
    end

    IO.puts("\n🔧 NEXT STEPS")
    IO.puts("  1. Fix broken links starting with high priority")
    IO.puts("  2. Run tests to ensure application routes work correctly")
    IO.puts("  3. Add this validation to your CI/CD pipeline")

    if show_suggestions do
      IO.puts("  4. Review suggestions above for specific fixes")
    else
      IO.puts("  4. Run with --fix-suggestions for detailed fix recommendations")
    end

    IO.puts("\n✅ Link validation complete!")

    # Return summary for potential integration
    %{
      total_links: results.total_links,
      valid_links: results.valid_links,
      broken_links: length(results.broken_links),
      health_percentage: health_percentage
    }
  end
end

# Run if called directly
if length(System.argv()) > 0 or !IEx.started?() do
  LinkValidator.run(System.argv())
end
