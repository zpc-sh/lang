defmodule MarkdownLd.JSONLD.Expand do
  @moduledoc """
  Minimal JSON-LD context expansion (offline, subset of 1.1).

  Supports:
  - Local `@context` objects (no remote fetching)
  - `@vocab` default IRI for terms
  - Prefix definitions: `"schema": "http://schema.org/"`
  - Term definitions: `"name": "schema:name"` or `"author": {"@id": "schema:author", "@type": "@id"}`
  - Expands property keys and `@type` values to IRIs
  - Coerces values with `@type: @id` to `{"@id": iri}`
  """

  @type ctx :: %{vocab: String.t() | nil, prefixes: map(), terms: map()}

  @spec expand(any()) :: any()
  def expand(data) do
    do_expand(data, %{})
  end

  defp do_expand(list, ctx) when is_list(list), do: Enum.map(list, &do_expand(&1, ctx))
  defp do_expand(map, ctx) when is_map(map) do
    {ctx2, map_wo_ctx} = pop_local_context(map, ctx)

    map_wo_ctx
    |> Enum.reduce(%{}, fn {k, v}, acc ->
      kk = to_string(k)
      cond do
        String.starts_with?(kk, "@") and kk != "@type" -> Map.put(acc, kk, v)
        kk == "@type" -> Map.put(acc, kk, expand_types(v, ctx2))
        true ->
          {iri, term_def} = resolve_term(kk, ctx2)
          new_val = coerce_value(v, term_def, ctx2)
          Map.put(acc, iri, new_val)
      end
    end)
  end
  defp do_expand(other, _ctx), do: other

  defp pop_local_context(map, ctx) do
    case Map.get(map, "@context") || Map.get(map, :"@context") do
      nil -> {ctx_from(ctx), Map.drop(map, ["@context", :"@context"])}
      c -> {merge_ctx(ctx_from(ctx), build_ctx(c)), Map.drop(map, ["@context", :"@context"])}
    end
  end

  defp ctx_from(%{vocab: _} = c), do: c
  defp ctx_from(_), do: %{vocab: nil, prefixes: %{}, terms: %{}}

  defp build_ctx(list) when is_list(list) do
    Enum.reduce(list, ctx_from(%{}), fn elem, acc ->
      merge_ctx(acc, build_ctx(elem))
    end)
  end
  defp build_ctx(map) when is_map(map) do
    Enum.reduce(map, ctx_from(%{}), fn {k, v}, acc ->
      kk = to_string(k)
      cond do
        kk == "@vocab" and is_binary(v) -> %{acc | vocab: v}
        is_binary(v) -> put_term_or_prefix(acc, kk, v)
        is_map(v) -> put_term_def(acc, kk, v)
        true -> acc
      end
    end)
  end
  defp build_ctx(_), do: ctx_from(%{})

  defp merge_ctx(a, b) do
    %{vocab: b.vocab || a.vocab, prefixes: Map.merge(a.prefixes, b.prefixes), terms: Map.merge(a.terms, b.terms)}
  end

  defp put_term_or_prefix(acc, key, val) do
    if String.ends_with?(val, "/") or String.ends_with?(val, "#") do
      # prefix
      %{acc | prefixes: Map.put(acc.prefixes, key, val)}
    else
      # term maps to id
      %{acc | terms: Map.put(acc.terms, key, %{id: val})}
    end
  end

  defp put_term_def(acc, key, %{"@id" => id} = defn), do: put_term_def(acc, key, Map.put(defn, :"@id", id))
  defp put_term_def(acc, key, %{:"@id" => id} = defn) do
    type = defn["@type"] || defn[:"@type"]
    %{acc | terms: Map.put(acc.terms, key, %{id: id, type: type})}
  end
  defp put_term_def(acc, key, _), do: acc

  defp resolve_term(key, ctx) do
    case ctx.terms[key] do
      %{id: id} = term -> {expand_iri(id, ctx), term}
      nil -> {expand_iri(key, ctx), %{}}
    end
  end

  defp expand_types(v, ctx) when is_list(v), do: Enum.map(v, &expand_types(&1, ctx))
  defp expand_types(v, ctx) when is_binary(v), do: expand_iri(v, ctx)
  defp expand_types(v, _ctx), do: v

  defp coerce_value(v, %{type: "@id"}, ctx) do
    cond do
      is_binary(v) -> %{"@id" => expand_iri(v, ctx)}
      is_map(v) and (Map.has_key?(v, "@id") or Map.has_key?(v, :"@id")) -> v
      true -> v
    end
  end
  defp coerce_value(v, _term, ctx) when is_map(v), do: do_expand(v, ctx)
  defp coerce_value(v, _term, ctx) when is_list(v), do: Enum.map(v, &coerce_value(&1, %{}, ctx))
  defp coerce_value(v, _term, _ctx), do: v

  defp expand_iri(iri, ctx) when is_binary(iri) do
    cond do
      String.starts_with?(iri, ["http://", "https://"]) -> iri
      String.contains?(iri, ":") ->
        [prefix, local] = String.split(iri, ":", parts: 2)
        base = ctx.prefixes[prefix]
        if base, do: base <> local, else: iri
      ctx.vocab -> ctx.vocab <> iri
      true -> iri
    end
  end
  defp expand_iri(other, _ctx), do: other
end
