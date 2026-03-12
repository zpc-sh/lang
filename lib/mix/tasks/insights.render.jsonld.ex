defmodule Mix.Tasks.Insights.Render.Jsonld do
  use Mix.Task
  @shortdoc "Render Insights from a JSON‑LD document (with optional namespace remap)"

  @moduledoc """
  Reads a JSON‑LD document, optionally remaps namespaces (e.g., explanations→insights),
  discovers entries arrays, and renders them into `Lang.Semantic.Insights.Insight` records.

      mix insights.render.jsonld path/to/layer.jsonld \
        --workspace WS --owner TEAM --source oci://owner/repo@ref \
        --remap explanations=insights --type-map Explanation=Insight

  Options:
  - --workspace: workspace id to stamp
  - --owner: owner/team id to stamp
  - --source: source URI (e.g., oci://...)
  - --remap: string replacement in all string values (repeatable), e.g. explanations=insights
  - --type-map: replace @type values (repeatable), e.g. Explanation=Insight
  """

  @switches [workspace: :string, owner: :string, source: :string, remap: :keep, "type-map": :keep]

  alias Lang.Semantic.Insights.Store

  @impl true
  def run(argv) do
    Mix.Task.run("loadpaths")
    {opts, args, _} = OptionParser.parse(argv, strict: @switches)
    path = List.first(args) || Mix.raise("usage: mix insights.render.jsonld file.jsonld [--workspace WS --owner TEAM --source URI --remap a=b --type-map A=B]")

    with {:ok, bin} <- File.read(path),
         {:ok, json} <- Jason.decode(bin) do
      remapped =
        json
        |> remap_strings(opts[:remap] || [])
        |> remap_types(opts[:"type-map"] || [])

      entries = find_entries(remapped)

      if entries == [] do
        Mix.shell().info("No entries[] found in document; nothing to render")
      end

      rendered =
        Enum.map(entries, fn entry ->
          attrs = normalize_entry(entry)
          attrs = maybe_put(attrs, :workspace_id, opts[:workspace])
          attrs = maybe_put(attrs, :owner_id, opts[:owner])
          attrs = maybe_put(attrs, :source_uri, opts[:source] || path)

          case Store.upsert(attrs) do
            {:ok, rec} -> %{id: rec.id, title: rec.title}
            {:error, reason} -> %{error: inspect(reason), title: attrs[:title]}
          end
        end)

      IO.puts(Jason.encode!(%{rendered: rendered, count: length(rendered)}))
    else
      {:error, reason} -> Mix.raise("render failed: #{inspect(reason)}")
    end
  end

  defp remap_strings(term, []), do: term
  defp remap_strings(term, rules) do
    Enum.reduce(List.wrap(rules), term, fn rule, acc ->
      case String.split(to_string(rule), "=", parts: 2) do
        [from, to] -> deep_replace(acc, from, to)
        _ -> acc
      end
    end)
  end

  defp remap_types(term, []), do: term
  defp remap_types(term, rules) do
    Enum.reduce(List.wrap(rules), term, fn rule, acc ->
      case String.split(to_string(rule), "=", parts: 2) do
        [from, to] -> deep_type_replace(acc, from, to)
        _ -> acc
      end
    end)
  end

  defp deep_replace(%{} = m, from, to) do
    m
    |> Enum.map(fn {k, v} -> {k, deep_replace(v, from, to)} end)
    |> Enum.into(%{})
  end
  defp deep_replace(list, from, to) when is_list(list), do: Enum.map(list, &deep_replace(&1, from, to))
  defp deep_replace(val, from, to) when is_binary(val), do: String.replace(val, from, to)
  defp deep_replace(other, _from, _to), do: other

  defp deep_type_replace(%{"@type" => type} = m, from, to) when is_binary(type) do
    Map.put(m, "@type", String.replace(type, from, to))
    |> Enum.map(fn {k, v} -> {k, deep_type_replace(v, from, to)} end)
    |> Enum.into(%{})
  end
  defp deep_type_replace(%{} = m, from, to) do
    m |> Enum.map(fn {k, v} -> {k, deep_type_replace(v, from, to)} end) |> Enum.into(%{})
  end
  defp deep_type_replace(list, from, to) when is_list(list), do: Enum.map(list, &deep_type_replace(&1, from, to))
  defp deep_type_replace(other, _from, _to), do: other

  defp find_entries(%{"entries" => list}) when is_list(list), do: list
  defp find_entries(%{"content" => %{"entries" => list}}) when is_list(list), do: list
  defp find_entries(%{} = m) do
    m
    |> Enum.flat_map(fn {_k, v} -> find_entries(v) end)
  end
  defp find_entries(list) when is_list(list), do: Enum.flat_map(list, &find_entries/1)
  defp find_entries(_), do: []

  defp normalize_entry(%{} = m) do
    %{
      title: m["title"] || m["name"] || "Untitled",
      content: m["content"] || m["text"] || "",
      tags: m["tags"] || [],
      lang: m["lang"] || "en",
      layer_type: m["layerType"] || m["ai:layerType"],
      metadata: Map.drop(m, ["title", "name", "content", "text", "tags", "lang", "layerType", "ai:layerType"]) || %{}
    }
  end

  defp maybe_put(map, _k, nil), do: map
  defp maybe_put(map, k, v), do: Map.put(map, k, v)
end

