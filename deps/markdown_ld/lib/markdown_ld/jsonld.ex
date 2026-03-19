defmodule MarkdownLd.JSONLD do
  @moduledoc """
  JSON-LD extraction (stub) and diff utilities.

  This module provides a placeholder extractor for JSON-LD triples and a graph
  diff that emits semantic add/remove/update suggestions. The extractor should
  be replaced with a proper frontmatter/JSON-LD parser.
  """

  alias MarkdownLd.Diff

  @typedoc "JSON-LD triple-like edge"
  @type triple :: %{s: String.t(), p: String.t(), o: String.t()}

  @doc """
  Extract JSON-LD triples from a markdown document.

  Sources supported:
  - Embedded code fences with languages: `json`, `json-ld`, `jsonld`, `application/ld+json`
  - YAML frontmatter stub: looks for `jsonld:` followed by an indented JSON object
  - Back-compat stub lines starting with `JSONLD: s,p,o`
  """
  @spec extract_triples(String.t()) :: [triple()]
  def extract_triples(text) do
    fence_triples = extract_from_fences(text)
    fm_triples = extract_from_frontmatter(text)
    stub_triples = extract_from_stub_lines(text)
    fence_triples ++ fm_triples ++ stub_triples
  end

  @doc """
  Compute a semantic diff between two docs' JSON-LD triples, producing Change
  operations: :jsonld_add, :jsonld_remove, and :jsonld_update (when same s,p and different o).
  """
  @spec diff(String.t(), String.t()) :: [Diff.Change.t()]
  def diff(old_text, new_text) do
    a = extract_triples(old_text)
    b = extract_triples(new_text)
    diff_triples(a, b)
  end

  @doc """
  Compute changes between two triple lists directly.
  """
  @spec diff_triples([triple()], [triple()]) :: [Diff.Change.t()]
  def diff_triples(a, b) do
    a_index = Map.new(a, fn t -> {{t.s, t.p}, t} end)
    b_index = Map.new(b, fn t -> {{t.s, t.p}, t} end)

    removes =
      a_index
      |> Enum.reject(fn {sp, _} -> Map.has_key?(b_index, sp) end)
      |> Enum.map(fn {_sp, t} -> Diff.change(:jsonld_remove, nil, %{triple: t}) end)

    adds =
      b_index
      |> Enum.reject(fn {sp, _} -> Map.has_key?(a_index, sp) end)
      |> Enum.map(fn {_sp, t} -> Diff.change(:jsonld_add, nil, %{triple: t}) end)

    updates =
      for {sp, old} <- a_index, new = b_index[sp], old && new, old.o != new.o do
        Diff.change(:jsonld_update, nil, %{before: old, after: new})
      end

    updates ++ removes ++ adds
  end

  # ——— Extractors ———

  @fence_langs MapSet.new(["json", "json-ld", "jsonld", "application/ld+json"])

  defp extract_from_fences(text) do
    lines = String.split(text, "\n", trim: false)
    do_fences(lines, nil, []) |> List.flatten()
  end

  defp do_fences([], _state, acc), do: Enum.reverse(acc)
  defp do_fences([line | rest], {:in, lang, buf}, acc) do
    cond do
      fence?(line) ->
        json = Enum.join(Enum.reverse(buf), "\n")
        triples = parse_jsonld_to_triples(json)
        do_fences(rest, nil, [triples | acc])
      true ->
        do_fences(rest, {:in, lang, [line | buf]}, acc)
    end
  end
  defp do_fences([line | rest], nil, acc) do
    case fence_lang(line) do
      {:fence, lang} ->
        if MapSet.member?(@fence_langs, String.downcase(lang)) do
          do_fences(rest, {:in, lang, []}, acc)
        else
          do_fences(rest, nil, acc)
        end
      _ -> do_fences(rest, nil, acc)
    end
  end

  defp fence_lang(line) do
    case Regex.run(~r/^```\s*([A-Za-z0-9_+\-\/]+)?\s*$/, line) do
      [_, lang] -> {:fence, lang}
      _ -> :no
    end
  end

  defp fence?(line), do: Regex.match?(~r/^```\s*$/, line)

  defp parse_jsonld_to_triples(json) do
    with {:ok, data} <- Jason.decode(json) do
      expanded = MarkdownLd.JSONLD.Expand.expand(data)
      triples_from_jsonld(expanded)
    else
      _ -> []
    end
  end

  defp extract_from_frontmatter(text) do
    case Regex.run(~r/\A---\s*\n([\s\S]*?)\n---\s*(?:\n|\z)/, text) do
      nil -> []
      [_, fm] ->
        # Attempt to find a json block after `jsonld:` key
        case Regex.run(~r/jsonld:\s*(\{[\s\S]*\})/i, fm) do
          [_, json] -> parse_jsonld_to_triples(json)
          _ -> []
        end
    end
  end

  defp extract_from_stub_lines(text) do
    text
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.filter(&String.starts_with?(&1, "JSONLD:"))
    |> Enum.map(fn "JSONLD:" <> rest ->
      parts = rest |> String.trim() |> String.split(",") |> Enum.map(&String.trim/1)
      case parts do
        [s, p, o] -> %{s: s, p: p, o: o}
        _ -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  # ——— JSON-LD to Triples ———

  defp triples_from_jsonld(list) when is_list(list) do
    list |> Enum.flat_map(&triples_from_jsonld/1)
  end
  defp triples_from_jsonld(map) when is_map(map) do
    s = Map.get(map, "@id") || Map.get(map, :"@id") || gen_subject(map)
    ctx = Map.get(map, "@context") || Map.get(map, :"@context")
    type = Map.get(map, "@type") || Map.get(map, :"@type")

    type_triples =
      cond do
        is_binary(type) -> [%{s: s, p: "rdf:type", o: type}]
        is_list(type) -> Enum.map(type, fn t -> %{s: s, p: "rdf:type", o: to_string(t)} end)
        true -> []
      end

    prop_triples =
      map
      |> Enum.flat_map(fn {k, v} ->
        kk = to_string(k)
        if String.starts_with?(kk, "@") do
          []
        else
          triples_for_value(s, kk, v)
        end
      end)

    type_triples ++ prop_triples
  end
  defp triples_from_jsonld(_), do: []

  defp triples_for_value(s, p, v) when is_binary(v), do: [%{s: s, p: p, o: v}]
  defp triples_for_value(s, p, v) when is_number(v), do: [%{s: s, p: p, o: to_string(v)}]
  defp triples_for_value(s, p, v) when is_boolean(v), do: [%{s: s, p: p, o: to_string(v)}]
  defp triples_for_value(s, p, v) when is_list(v) do
    Enum.flat_map(v, fn e -> triples_for_value(s, p, e) end)
  end
  defp triples_for_value(s, p, v) when is_map(v) do
    case Map.get(v, "@id") || Map.get(v, :"@id") do
      nil -> [%{s: s, p: p, o: Jason.encode!(v)}]
      id -> [%{s: s, p: p, o: id}] ++ triples_from_jsonld(v)
    end
  end

  defp gen_subject(map) do
    # Deterministic pseudo-subject from JSON
    {:ok, json} = Jason.encode(map)
    "_:" <> (:crypto.hash(:sha256, json) |> Base.encode16(case: :lower) |> binary_part(0, 12))
  end
end
