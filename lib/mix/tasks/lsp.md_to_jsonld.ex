defmodule Mix.Tasks.Lsp.MdToJsonld do
  use Mix.Task
  @shortdoc "Convert docs/lsp.md table into JSON-LD spec files"
  @moduledoc """
  Parses `docs/lsp.md` and emits JSON-LD files under `priv/lsp/specs` (default) —
  one file per method.

  Usage:
    mix lsp.md_to_jsonld            # writes to priv/lsp/specs
    mix lsp.md_to_jsonld path/to/outdir
  """

  alias Lang.Native.FSScanner

  @default_out "priv/lsp/specs"

  @impl true
  def run(args) do
    # Load paths without compiling the whole app
    Mix.Task.run("loadpaths")

    out_dir =
      case args do
        [dir] -> dir
        _ -> @default_out
      end

    with {:ok, md} <- read_markdown("docs/lsp.md"),
         rows <- extract_rows(md) do
      Mix.shell().info("Found #{length(rows)} method rows in docs/lsp.md")
      ensure_dir!(out_dir)

      Enum.each(rows, fn row ->
        jsonld = to_jsonld(row)
        path = Path.join(out_dir, filename_for(row.method))
        write_json!(path, jsonld)
        Mix.shell().info("wrote #{path}")
      end)
    else
      {:error, reason} -> Mix.raise("failed to read docs/lsp.md: #{inspect(reason)}")
    end
  end

  defp read_markdown(path) do
    case FSScanner.preview(path, max_lines: 100_000) do
      {:ok, lines} when is_list(lines) -> {:ok, Enum.join(lines, "\n")}
      {:ok, bin} when is_binary(bin) -> {:ok, bin}
      other -> other
    end
  end

  # Extract table rows of the form:
  # | `method` | STATUS | Priority | Description | `impl_file` |
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

      _ ->
        nil
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

  defp to_jsonld(%{
         method: method,
         status: status,
         priority: priority,
         description: desc,
         impl_file: file
       }) do
    category = derive_category(method)

    %{
      "@context" => %{
        "lang" => "https://lang.nulity.com/schema/v1/",
        "xsd" => "http://www.w3.org/2001/XMLSchema#"
      },
      "@type" => "lang:Function",
      "@id" => "lang:" <> method,
      "name" => method,
      "category" => category,
      "description" => desc,
      "implementation" => %{
        "status" => status,
        "priority" => priority,
        "file" => file
      }
    }
  end

  defp derive_category(name) do
    case String.split(name, ".") do
      ["lang", cat | _] -> cat
      [cat | _] -> cat
      _ -> "other"
    end
  end

  defp filename_for(method) do
    method |> String.replace(".", "_") |> Kernel.<>(".jsonld")
  end

  defp ensure_dir!(path), do: File.mkdir_p!(path)

  defp write_json!(path, map) do
    json = Jason.encode!(map, pretty: true)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, json)
  end
end
