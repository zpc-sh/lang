defmodule MarkdownLD.JSONLD do
  @moduledoc """
  Minimal JSON-LD helpers used across the project.

  This module centralizes tolerant accessors, simple compact/expand without
  remote context fetches, and a basic runtime-task normalization.

  Note: For full JSON-LD 1.1, prefer a canonicalizer/expander. This module
  intentionally avoids network access and keeps operations local and fast.
  """

  # Normalize and tolerant getters
  def normalize(%{"@context" => ctx} = map) when is_map(ctx), do: {map, ctx}
  def normalize(%{"@context" => _} = map), do: {map, %{}}
  def normalize(map) when is_map(map), do: {map, %{}}
  def normalize(other), do: {other, %{}}

  def get(map, term, default \\ nil) when is_map(map) do
    {data, ctx} = normalize(map)

    cond do
      Map.has_key?(data, term) -> Map.get(data, term)
      iri = ctx_iri(ctx, term) -> Map.get(data, iri, default)
      true -> Map.get(data, term, default)
    end
  end

  def get_list(map, term) do
    case get(map, term) do
      nil -> []
      v when is_list(v) -> v
      v -> [v]
    end
  end

  def types(map) when is_map(map) do
    case Map.get(map, "@type") do
      nil ->
        case Map.get(map, "type") do
          nil -> []
          t when is_list(t) -> Enum.map(t, &to_string/1)
          t -> [to_string(t)]
        end

      t when is_list(t) ->
        Enum.map(t, &to_string/1)

      t ->
        [to_string(t)]
    end
  end

  def types(_), do: []

  # Simple compact/expand (local context only)
  def compact(doc, context) do
    {map, _} = normalize(doc)
    ctx = normalize_context(context)
    inv = invert_context(ctx)
    {do_compact(map, inv), ctx}
  end

  def expand(doc, context) do
    {map, _} = normalize(doc)
    ctx = normalize_context(context)
    {do_expand(map, ctx), ctx}
  end

  # Internal helpers
  defp ctx_iri(ctx, term) when is_map(ctx) do
    case Map.get(ctx, term) do
      v when is_binary(v) -> v
      _ -> nil
    end
  end

  defp normalize_context(%{} = ctx), do: ctx
  defp normalize_context(_), do: %{}

  defp invert_context(ctx) do
    Enum.reduce(ctx, %{}, fn {term, iri}, acc ->
      if is_binary(iri), do: Map.put(acc, iri, term), else: acc
    end)
  end

  defp do_compact(%{} = map, inv_ctx) do
    map
    |> Enum.map(fn {k, v} ->
      key = if is_binary(k), do: Map.get(inv_ctx, k, k), else: k
      {key, do_compact(v, inv_ctx)}
    end)
    |> Enum.into(%{})
  end

  defp do_compact(list, inv_ctx) when is_list(list), do: Enum.map(list, &do_compact(&1, inv_ctx))
  defp do_compact(other, _), do: other

  defp do_expand(%{} = map, ctx) do
    map
    |> Enum.map(fn {k, v} ->
      key =
        case k do
          s when is_binary(s) ->
            if String.starts_with?(s, "@") do
              s
            else
              Map.get(ctx, s, s)
            end

          other ->
            other
        end

      {key, do_expand(v, ctx)}
    end)
    |> Enum.into(%{})
  end

  defp do_expand(list, ctx) when is_list(list), do: Enum.map(list, &do_expand(&1, ctx))
  defp do_expand(other, _), do: other
end
