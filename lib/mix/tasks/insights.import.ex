defmodule Mix.Tasks.Insights.Import do
  use Mix.Task
  @shortdoc "Import Insights from a JSON or JSON‑LD file (entries[])"

  @moduledoc """
  Imports insights from a JSON/JSON‑LD file that contains an `entries` array with fields
  like `{title, content, tags, lang}`. Adds optional metadata and source_uri.

      mix insights.import path/to/file.json --workspace WS --owner TEAM --source oci://...
  """

  @switches [workspace: :string, owner: :string, source: :string]

  alias Lang.Semantic.Insights.Store

  @impl true
  def run(argv) do
    Mix.Task.run("loadpaths")
    {opts, args, _} = OptionParser.parse(argv, strict: @switches)
    path = List.first(args) || Mix.raise("usage: mix insights.import file.json [--workspace WS --owner TEAM --source URI]")

    with {:ok, bin} <- File.read(path),
         {:ok, json} <- Jason.decode(bin),
         entries when is_list(entries) <- Map.get(json, "entries") || Mix.raise("file must contain entries[]") do
      imported =
        entries
        |> Enum.map(&normalize_entry/1)
        |> Enum.map(fn attrs ->
          attrs =
            attrs
            |> maybe_put(:workspace_id, opts[:workspace])
            |> maybe_put(:owner_id, opts[:owner])
            |> maybe_put(:source_uri, opts[:source])

          case Store.upsert(attrs) do
            {:ok, rec} -> %{id: rec.id, title: rec.title}
            {:error, reason} -> %{error: inspect(reason)}
          end
        end)

      Mix.shell().info("Imported #{Enum.count(Enum.filter(imported, &Map.has_key?(&1, :id)))} insights")
      IO.puts(Jason.encode!(%{imported: imported}))
    else
      {:error, reason} -> Mix.raise("import failed: #{inspect(reason)}")
    end
  end

  defp normalize_entry(%{} = m) do
    %{
      title: m["title"] || m["name"] || "Untitled",
      content: m["content"] || m["text"] || "",
      tags: m["tags"] || [],
      lang: m["lang"] || "en",
      metadata: Map.drop(m, ["title", "name", "content", "text", "tags", "lang"]) || %{}
    }
  end

  defp maybe_put(map, _k, nil), do: map
  defp maybe_put(map, k, v), do: Map.put(map, k, v)
end

