defmodule Mix.Tasks.Lsp.Validate do
  use Mix.Task
  @shortdoc "Validate docs/lsp.md rows and JSON-LD/YAML specs for ingestion"

  alias Lang.Native.FSScanner
  alias Nullity.CDFM.Spec
  alias Nullity.CDFM.Validator

  @impl true
  def run(args) do
    # Load paths without compiling the whole app
    Mix.Task.run("loadpaths")

    out = Keyword.get(parse_args(args), :out, "priv/lsp/specs")
    errors = []

    # 1) Validate docs/lsp.md table rows
    errors = errors ++ validate_docs()

    # 2) Validate specs in directory
    errors = errors ++ validate_specs(out)

    if errors == [] do
      Mix.shell().info("Validation OK: docs and specs look good")
    else
      Enum.each(errors, &Mix.shell().error/1)
      Mix.raise("Validation failed: #{length(errors)} issue(s)")
    end
  end

  defp parse_args(_args), do: []

  defp validate_docs do
    case FSScanner.preview("docs/lsp.md", max_lines: 100_000) do
      {:ok, lines} ->
        md = Enum.join(List.wrap(lines), "\n")
        rows = extract_rows(md)
        rows
        |> Enum.flat_map(fn r ->
          Validator.validate_doc_row(r)
          |> Enum.map(fn issue -> "docs/lsp.md: #{r.method}: #{issue}" end)
        end)
      {:error, reason} -> ["failed to read docs/lsp.md: #{inspect(reason)}"]
    end
  end

  defp validate_specs(dir) do
    files = case FSScanner.search(dir, ~S/\.(jsonld|ya?ml)$/, max_results: 50_000) do
      {:ok, results} when is_list(results) ->
        Enum.map(results, fn
          %{:path => path} -> path
          %{"path" => path} -> path
          path when is_binary(path) -> path
        end)
      _ -> []
    end

    files
    |> Enum.flat_map(&validate_spec_file/1)
  end

  defp validate_spec_file(path) do
    case FSScanner.preview(path, max_lines: 100_000) do
      {:ok, lines} -> validate_spec_content(path, Enum.join(List.wrap(lines), "\n"))
      {:error, reason} -> ["#{path}: read error #{inspect(reason)}"]
    end
  end

  defp validate_spec_content(path, content) do
    try do
      Spec.parse_spec!(content)
      |> Enum.flat_map(fn s ->
        Validator.validate_spec(s)
        |> Enum.map(fn issue -> "#{path}: #{s.name || s.id}: #{issue}" end)
      end)
    rescue
      e -> ["#{path}: parse error #{inspect(e)}"]
    end
  end

  # Same row extraction as md_to_jsonld, kept local to avoid cross-task deps
  defp extract_rows(md) do
    md
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.filter(&String.starts_with?(&1, "|"))
    |> Enum.reject(&String.contains?(&1, "| Method |"))
    |> Enum.reject(&String.match?(&1, ~r/^\|\s*-+\s*\|/))
    |> Enum.map(&parse_row/1)
    |> Enum.reject(&is_nil/1)
  end

  defp parse_row(line) do
    parts =
      line
      |> String.trim_leading("|")
      |> String.trim_trailing("|")
      |> String.split("|")
      |> Enum.map(&String.trim/1)

    case parts do
      [method_cell, status_cell, priority_cell, desc_cell, file_cell] ->
        method = method_from_cell(method_cell)
        status = status_from_cell(status_cell)
        priority = priority_cell
        desc = desc_cell
        file = impl_from_cell(file_cell)
        %{method: method, status: status, priority: priority, description: desc, impl_file: file}
      _ -> nil
    end
  end

  defp method_from_cell(cell) do
    case Regex.run(~r/`([^`]+)`/, cell) do
      [_, m] -> m
      _ -> cell
    end
  end

  defp impl_from_cell(cell) do
    case Regex.run(~r/`([^`]+)`/, cell) do
      [_, p] -> p
      _ -> cell
    end
  end

  defp status_from_cell(cell) do
    cond do
      String.contains?(cell, "✅") -> "implemented"
      String.contains?(cell, "🚧") -> "in_progress"
      String.contains?(cell, "❌") -> "not_implemented"
      true -> "unknown"
    end
  end
end
