defmodule Lang.Dev.DocPolicy do
  @moduledoc """
  Repository documentation policy enforcement.

  - Only markdown under ./docs is considered curated/trusted
  - Markdown outside ./docs must be allowlisted via .doc_allowlist
  - Trusted docs should include YAML frontmatter with `trusted: true`
  """

  @allowlist_file ".doc_allowlist"

  @spec markdown_files() :: [String.t()]
  def markdown_files do
    root = File.cwd!()
    files = Path.wildcard(Path.join(root, "**/*.md"), match_dot: false)
    Enum.map(files, &Path.relative_to(&1, root))
  end

  @spec in_docs?(String.t()) :: boolean
  def in_docs?(path), do: String.starts_with?(Path.expand(path), Path.expand("docs"))

  @spec allowlisted?(String.t()) :: boolean
  def allowlisted?(path) do
    patterns = load_allowlist()
    Enum.any?(patterns, fn pat -> :filelib.wildcard_match(pat, path) end)
  end

  defp load_allowlist do
    case File.read(@allowlist_file) do
      {:ok, content} ->
        content
        |> String.split("\n")
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == "" or String.starts_with?(&1, "#")))
      _ -> []
    end
  end

  @doc """
  Verify trusted docs under ./docs include `trusted: true` in frontmatter.
  Returns list of {path, :missing_trusted} failures.
  """
  @spec check_trusted_frontmatter() :: list({String.t(), atom})
  def check_trusted_frontmatter do
    markdown_files()
    |> Enum.filter(&in_docs?/1)
    |> Enum.flat_map(fn path ->
      case File.read(path) do
        {:ok, content} ->
          if trusted_frontmatter?(content), do: [], else: [{path, :missing_trusted}]
        _ -> [{path, :unreadable}]
      end
    end)
  end

  defp trusted_frontmatter?(content) do
    case String.split(content, "\n", parts: 2) do
      ["---" <> _ | _] ->
        # crude parse: read first block between --- and ---
        case String.split(content, "\n---\n", parts: 2) do
          [front, _rest] -> String.contains?(front, "trusted: true")
          _ -> false
        end
      _ -> false
    end
  end

  @doc """
  Find markdown files outside ./docs that are not allowlisted.
  Returns list of paths.
  """
  @spec untrusted_markdown_outside_docs() :: [String.t()]
  def untrusted_markdown_outside_docs do
    markdown_files()
    |> Enum.reject(&in_docs?/1)
    |> Enum.reject(&allowlisted?/1)
  end
end

