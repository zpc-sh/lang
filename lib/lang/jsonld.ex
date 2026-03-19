defmodule Lang.JSONLD do
  @moduledoc """
  Minimal JSON-LD helpers to keep payloads native while extracting
  fields for internal processing. No external deps, tolerant lookups.
  """

  @doc "Normalize params and return {data, context_map}."
  def normalize(%{"@context" => ctx} = map) when is_map(ctx), do: {map, ctx}
  # ignore remote
  def normalize(%{"@context" => ctx} = map) when is_binary(ctx), do: {map, %{}}
  def normalize(map) when is_map(map), do: {map, %{}}
  def normalize(other), do: {other, %{}}

  @doc "Get a value for a term; tries compact key, IRI via @context, and plain key."
  def get(map, term, default \\ nil) when is_map(map) do
    {data, ctx} = normalize(map)

    cond do
      Map.has_key?(data, term) -> Map.get(data, term)
      iri = ctx_iri(ctx, term) -> Map.get(data, iri, default)
      true -> Map.get(data, term, default)
    end
  end

  @doc "Get a list value; coerces singletons to a list."
  def get_list(map, term) do
    case get(map, term) do
      nil -> []
      v when is_list(v) -> v
      v -> [v]
    end
  end

  @doc "Get @type as list of strings."
  def types(map) when is_map(map) do
    case Map.get(map, "@type") do
      nil ->
        # sometimes 'type' used
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

  @doc "Convert JSON-LD task into internal runtime map (keeping original under :ld)."
  def to_runtime_task(task) when is_map(task) do
    {data, _ctx} = normalize(task)
    t = pick_task_type(types(data))

    %{
      ld: data,
      type: t,
      goal: get(data, "goal"),
      content: get(data, "content"),
      strategy: normalize_strategy(get(data, "strategy")),
      required_capabilities: normalize_caps(get_list(data, "requiredCapabilities"))
    }
  end

  def to_runtime_task(other), do: %{ld: other, type: :analysis}

  # --- helpers ---
  defp ctx_iri(ctx, term) when is_map(ctx) do
    case Map.get(ctx, term) do
      v when is_binary(v) -> v
      _ -> nil
    end
  end

  defp pick_task_type(types) do
    # prefer lang:* types
    cond do
      Enum.any?(types, &String.ends_with?(&1, "AnalysisTask")) -> :analysis
      Enum.any?(types, &String.ends_with?(&1, "GenerationTask")) -> :generation
      Enum.any?(types, &String.ends_with?(&1, "CoordinationTask")) -> :coordination
      Enum.any?(types, &String.ends_with?(&1, "SecurityScan")) -> :security_scan
      true -> :analysis
    end
  end

  defp normalize_strategy(nil), do: :fanout

  defp normalize_strategy(s) when is_binary(s) do
    case String.downcase(s) do
      "fanout" -> :fanout
      "first_success" -> :first_success
      "map_reduce" -> :map_reduce
      _ -> :fanout
    end
  end

  defp normalize_strategy(s) when is_atom(s), do: s
  defp normalize_strategy(_), do: :fanout

  defp normalize_caps(list) when is_list(list) do
    list
    |> Enum.map(&to_string/1)
    |> Enum.map(&String.downcase/1)
    |> Enum.map(fn name ->
      case name do
        "read_only" -> :read_only
        "analysis" -> :analysis
        "explain" -> :analysis
        "single_file_edit" -> :single_file_edit
        "local_generation" -> :local_generation
        "multi_file_coordination" -> :multi_file_coordination
        "refactoring" -> :refactoring
        "architecture_changes" -> :architecture_changes
        "system_wide" -> :system_wide
        _ -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp normalize_caps(_), do: []

  # ---------------------------------------------------------------------------
  # Minimal compact/expand helpers (no remote fetch)
  # ---------------------------------------------------------------------------
  @doc """
  Compact a JSON/JSON-LD document using a local context map.

  - Rewrites keys that are IRIs to their compact terms from `context`.
  - Recurses into nested maps/lists.
  - Returns `{compacted_map, context_map}`. Remote string contexts are ignored.
  """
  def compact(doc, context) do
    {map, _} = normalize(doc)
    ctx = normalize_context(context)
    inv = invert_context(ctx)
    {do_compact(map, inv), ctx}
  end

  @doc """
  Expand a compacted JSON/JSON-LD document using a local context map.

  - Rewrites keys that are compact terms to their IRI from `context`.
  - Recurses into nested maps/lists.
  - Returns `{expanded_map, context_map}`.
  """
  def expand(doc, context) do
    {map, _} = normalize(doc)
    ctx = normalize_context(context)
    {do_expand(map, ctx), ctx}
  end

  # --- internal ---
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
          "@" <> _ = s when is_binary(s) -> s
          s when is_binary(s) -> Map.get(ctx, s, s)
          other -> other
        end

      {key, do_expand(v, ctx)}
    end)
    |> Enum.into(%{})
  end

  defp do_expand(list, ctx) when is_list(list), do: Enum.map(list, &do_expand(&1, ctx))
  defp do_expand(other, _), do: other
end
