#!/usr/bin/env elixir

defmodule LinkFinder do
  @moduledoc """
  Simple link extraction script for LANG platform.
  Finds all links in documentation and templates without complex validation.
  """

  def run(args \\ []) do
    IO.puts("\n🔍 LANG Link Discovery")
    IO.puts("=" |> String.duplicate(50))

    verbose = "--verbose" in args

    results = %{
      total_files: 0,
      total_links: 0,
      links_by_file: []
    }

    # Find all relevant files
    files = find_all_files()

    if verbose do
      IO.puts("Found #{length(files)} files to scan")
    end

    # Scan each file
    results =
      Enum.reduce(files, results, fn file, acc ->
        scan_file(file, acc, verbose)
      end)

    # Generate report
    generate_report(results)
  end

  defp find_all_files do
    # Documentation files
    doc_files =
      [
        # Manual docs
        Path.wildcard("priv/docs/**/*.md"),
        # Generated docs
        Path.wildcard("priv/static/docs/**/*.md"),
        # Root docs
        ["README.md", "AGENTS.md", "DEPLOYMENT_GUIDE.md", "USER_FLOW_ANALYSIS.md"]
        |> Enum.filter(&File.exists?/1)
      ]
      |> List.flatten()

    # Template files
    template_files =
      [
        Path.wildcard("lib/lang_web/**/*.heex"),
        Path.wildcard("lib/lang_web/**/*_live.ex")
      ]
      |> List.flatten()

    doc_files ++ template_files
  end

  defp scan_file(file_path, results, verbose) do
    if verbose do
      IO.puts("  📄 Scanning: #{file_path}")
    end

    content = File.read!(file_path)
    links = extract_all_links(content)

    if verbose and length(links) > 0 do
      IO.puts("    Found #{length(links)} links")
    end

    file_data = %{
      file: file_path,
      links: links,
      link_count: length(links)
    }

    %{
      results
      | total_files: results.total_files + 1,
        total_links: results.total_links + length(links),
        links_by_file: [file_data | results.links_by_file]
    }
  end

  defp extract_all_links(content) do
    lines = String.split(content, "\n", trim: false)

    lines
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_num} ->
      extract_line_links(line, line_num)
    end)
    |> Enum.uniq_by(fn {url, _, _} -> url end)
  end

  defp extract_line_links(line, line_num) do
    patterns = [
      # Markdown links: [text](url)
      {~r/\[([^\]]*)\]\(([^)]+)\)/,
       fn [_full, text, url] ->
         {url, line_num, "[#{text}](#{url})"}
       end},

      # Angle bracket links: <url>
      {~r/<(https?:\/\/[^>]+)>/,
       fn [_full, url] ->
         {url, line_num, "<#{url}>"}
       end},

      # href attributes: href="url"
      {~r/href=["']([^"']+)["']/,
       fn [_full, url] ->
         {url, line_num, "href=\"#{url}\""}
       end},

      # Phoenix navigate/patch: navigate={url}
      {~r/(?:navigate|patch)=["'{]([^"'}]+)["'}]/,
       fn [_full, url] ->
         {url, line_num, "navigate/patch=\"#{url}\""}
       end},

      # Bare URLs
      {~r/https?:\/\/[^\s\)\]>]+/,
       fn [url] ->
         {url, line_num, url}
       end}
    ]

    Enum.flat_map(patterns, fn {regex, mapper} ->
      Regex.scan(regex, line)
      |> Enum.map(mapper)
    end)
  end

  defp generate_report(results) do
    IO.puts("\n📊 LINK DISCOVERY REPORT")
    IO.puts("=" |> String.duplicate(50))

    IO.puts("\n📈 SUMMARY")
    IO.puts("Files scanned: #{results.total_files}")
    IO.puts("Total links found: #{results.total_links}")

    # Group by link type
    all_links = Enum.flat_map(results.links_by_file, & &1.links)

    {internal_links, external_links} =
      Enum.split_with(all_links, fn {url, _, _} ->
        !String.starts_with?(url, ["http://", "https://"])
      end)

    IO.puts("Internal links: #{length(internal_links)}")
    IO.puts("External links: #{length(external_links)}")

    # Show files with most links
    IO.puts("\n📄 FILES WITH MOST LINKS")

    results.links_by_file
    |> Enum.sort_by(& &1.link_count, :desc)
    |> Enum.take(10)
    |> Enum.each(fn file_data ->
      IO.puts("  #{file_data.link_count} links: #{file_data.file}")
    end)

    # Show common external domains
    IO.puts("\n🌐 EXTERNAL DOMAINS")

    external_links
    |> Enum.map(fn {url, _, _} ->
      URI.parse(url).host || "invalid-url"
    end)
    |> Enum.frequencies()
    |> Enum.sort_by(fn {_, count} -> count end, :desc)
    |> Enum.take(10)
    |> Enum.each(fn {domain, count} ->
      IO.puts("  #{count}x #{domain}")
    end)

    # Show all internal links
    IO.puts("\n🏠 INTERNAL LINKS")

    internal_links
    |> Enum.map(fn {url, _, _} -> url end)
    |> Enum.frequencies()
    |> Enum.sort()
    |> Enum.each(fn {url, count} ->
      IO.puts("  #{count}x #{url}")
    end)

    # Show suspicious patterns
    IO.puts("\n⚠️  POTENTIALLY PROBLEMATIC LINKS")

    suspicious =
      all_links
      |> Enum.filter(fn {url, _, _} ->
        String.contains?(url, ["lang.nocsi.com", "TODO", "FIXME", "localhost", "127.0.0.1"])
      end)

    if length(suspicious) > 0 do
      Enum.each(suspicious, fn {url, line, context} ->
        file =
          Enum.find(results.links_by_file, fn f ->
            Enum.any?(f.links, fn {u, _, _} -> u == url end)
          end)

        IO.puts("  ⚠️  #{url}")
        IO.puts("     File: #{file.file}:#{line}")
        IO.puts("     Context: #{context}")
        IO.puts("")
      end)
    else
      IO.puts("  ✅ No suspicious links found")
    end

    IO.puts("\n✅ Link discovery complete!")
    IO.puts("Run with --verbose for detailed scanning output")

    results
  end
end

# Run if called directly
if length(System.argv()) > 0 do
  LinkFinder.run(System.argv())
end
