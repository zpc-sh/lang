defmodule Lang.Dev.DocSanitizer do
  @moduledoc """
  Scans documentation/content files for prompt-injection patterns and returns findings.

  - Uses Lang.Native.FSScanner for fast traversal/preview when available, with safe fallbacks
  - Reuses Lang.Dev.InjectionScanner heuristics
  - Designed for CI/precommit gating and ad-hoc audits via Mix tasks
  """

  @type finding :: %{
          file: String.t(),
          line: non_neg_integer(),
          type: atom(),
          severity: :low | :medium | :high,
          snippet: String.t()
        }

  @default_globs ["docs", "AGENTS.md", "AGENTS.codex.md", "CONTRIBUTING.md", "README.md", "priv/secret"]
  @text_exts ~w(.md .mdx .markdown .txt)

  def scan(paths \\ @default_globs, opts \\ []) do
    paths
    |> Enum.flat_map(&expand_path/1)
    |> Enum.filter(&text_like?/1)
    |> Enum.flat_map(&scan_file(&1, opts))
  end

  defp expand_path(path) do
    cond do
      File.dir?(path) -> list_dir(path)
      File.regular?(path) -> [path]
      true -> []
    end
  end

  defp list_dir(dir) do
    # Prefer NIF scanner; fallback to Elixir
    case ensure_nif(:scan) do
      :nif ->
        case Lang.Native.FSScanner.scan(dir, max_depth: 32) do
          {:ok, %{tree: tree}} ->
            tree
            |> Enum.flat_map(fn entry ->
              case entry do
                %{"name" => name, "type" => "file"} -> [Path.join(dir, name)]
                %{name: name, type: "file"} -> [Path.join(dir, name)]
                %{name: name, type: :file} -> [Path.join(dir, name)]
                _ -> []
              end
            end)
          _ -> fallback_list(dir)
        end
      :fallback -> fallback_list(dir)
    end
  end

  defp fallback_list(dir) do
    case File.ls(dir) do
      {:ok, items} -> Enum.map(items, &Path.join(dir, &1)) |> Enum.flat_map(&expand_path/1)
      _ -> []
    end
  end

  defp text_like?(path) do
    ext = Path.extname(path)
    String.downcase(ext) in @text_exts
  end

  defp scan_file(path, _opts) do
    content = preview_all(path)
    findings = Lang.Dev.InjectionScanner.scan_markdown(content)
    Enum.map(findings, &Map.put(&1, :file, path))
  rescue
    _ -> []
  end

  defp preview_all(path) do
    case ensure_nif(:preview) do
      :nif ->
        case Lang.Native.FSScanner.preview(path, max_lines: 2_000_000) do
          {:ok, lines} -> Enum.join(lines, "\n")
          _ -> File.read!(path)
        end
      :fallback -> File.read!(path)
    end
  end

  defp ensure_nif(_op) do
    case Code.ensure_loaded(Lang.Native.FSScanner) do
      {:module, _} -> :nif
      _ -> :fallback
    end
  end
end

