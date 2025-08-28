defmodule LangWeb.Api.V2.SpatialController do
  @moduledoc """
  Spatial Map API v2

  Provides normalized access to the latest project Spatial Map with pagination
  over symbols and relations. Supports file-scoped pagination via the `file`
  filter and returns both filtered totals and overall counts in `meta`.
  """

  use LangWeb, :controller
  require Logger

  action_fallback LangWeb.Api.FallbackController

  @default_page 1
  @default_page_size 200
  @max_page_size 1000

  @doc """
  GET /api/v2/spatial/map/:project_id

  Query params:
  - section: "symbols" | "relations" | "all" (default: "all")
  - page, page_size: pagination controls (default: 1, 200; max page_size 1000)
  - Filters for symbols: kind, language, file (file-scoped pagination)
  - Filters for relations: type, language, target_kind, from, to, file (alias for from), target_file (when path-like)
  - counts_only: when true, returns only counts/metadata (no items)
  """
  def map_summary(conn, %{"project_id" => project_id} = params) do
    with {:ok, summary} <- Lang.Spatial.latest_map_summary(project_id) do
      section = Map.get(params, "section", "all")
      {page, page_size} = normalize_pagination(params)
      counts_only? = truthy?(Map.get(params, "counts_only"))

      symbol_filters = Map.take(params, ["kind", "language", "file"]) |> atoms_if_present()
      relation_filters = Map.take(params, ["type", "language", "target_kind", "from", "to", "file", "target_file"]) |> atoms_if_present()

      # Symbols filtering, pagination, and counts
      {symbols_page, symbols_meta} =
        if section in ["all", "symbols"] do
          all_symbols = summary.symbols || []
          filtered_symbols = Enum.filter(all_symbols, &filter_symbol(&1, symbol_filters))
          {page_items, meta} = paginate(filtered_symbols, page, page_size)
          %{
            total: length(filtered_symbols),
            total_all: length(all_symbols),
            page: page,
            page_size: page_size,
            counts_all_by_language: counts_by_language(all_symbols),
            counts_by_language: counts_by_language(filtered_symbols)
          }
          |> then(fn m -> {page_items, m} end)
        else
          {[], %{total: 0, total_all: 0, page: page, page_size: page_size, counts_all_by_language: %{}, counts_by_language: %{}}}
        end

      # Relations filtering, pagination, and counts
      {relations_page, relations_meta} =
        if section in ["all", "relations"] do
          all_relations = summary.relations || []
          filtered_relations = Enum.filter(all_relations, &filter_relation(&1, relation_filters))
          {page_items, meta} = paginate(filtered_relations, page, page_size)
          %{
            total: length(filtered_relations),
            total_all: length(all_relations),
            page: page,
            page_size: page_size,
            counts_all_by_language: counts_by_language(all_relations),
            counts_by_language: counts_by_language(filtered_relations)
          }
          |> then(fn m -> {page_items, m} end)
        else
          {[], %{total: 0, total_all: 0, page: page, page_size: page_size, counts_all_by_language: %{}, counts_by_language: %{}}}
        end

      body = %{
        map_id: summary.map_id,
        project_id: summary.project_id,
        generated_at: summary.generated_at,
        stats: summary.stats,
        section: section,
        symbols: if(counts_only?, do: [], else: symbols_page),
        relations: if(counts_only?, do: [], else: relations_page),
        meta: %{
          symbols: symbols_meta,
          relations: relations_meta,
          filters: %{
            symbols: symbol_filters,
            relations: relation_filters
          }
        }
      }

      json(conn, body)
    else
      {:ok, nil} ->
        conn |> put_status(:not_found) |> json(%{error: "no map available"})

      {:error, reason} ->
        Logger.error("map_summary failed", reason: inspect(reason))
        conn |> put_status(:internal_server_error) |> json(%{error: "internal_error"})
    end
  end

  # Pagination helpers
  defp normalize_pagination(params) do
    page = params |> Map.get("page", @default_page) |> to_int(@default_page)
    page_size =
      params
      |> Map.get("page_size", @default_page_size)
      |> to_int(@default_page_size)
      |> min(@max_page_size)

    page = if page < 1, do: 1, else: page
    page_size = if page_size < 1, do: @default_page_size, else: page_size
    {page, page_size}
  end

  defp to_int(val, default) when is_binary(val) do
    case Integer.parse(val) do
      {i, _} -> i
      _ -> default
    end
  end

  defp to_int(val, _default) when is_integer(val), do: val
  defp to_int(_, default), do: default

  defp paginate(list, page, page_size) do
    list = list || []
    offset = (page - 1) * page_size
    data = list |> Enum.drop(offset) |> Enum.take(page_size)
    {data, %{total: length(list), page: page, page_size: page_size}}
  end

  # Filtering
  defp filter_symbol(item, filters) do
    Enum.all?([
      eq_or_nil(item.kind, Map.get(filters, :kind)),
      eq_or_nil(item.language, Map.get(filters, :language)),
      eq_or_nil(item.file, Map.get(filters, :file))
    ])
  end

  defp filter_relation(item, filters) do
    Enum.all?([
      eq_or_nil(item.type, Map.get(filters, :type)),
      eq_or_nil(item.language, Map.get(filters, :language)),
      eq_or_nil(item.target_kind, Map.get(filters, :target_kind)),
      eq_or_nil(item.from, Map.get(filters, :from)),
      # allow file= as alias for from
      eq_or_nil(item.from, Map.get(filters, :file) || Map.get(filters, :from)),
      eq_or_nil(item.to, Map.get(filters, :to)),
      match_target_file(item, Map.get(filters, :target_file))
    ])
  end

  defp eq_or_nil(_val, nil), do: true
  defp eq_or_nil(val, val), do: true
  defp eq_or_nil(_val, _), do: false

  # Only match target_file when the relation points to a path-like target
  defp match_target_file(_item, nil), do: true
  defp match_target_file(%{target_kind: tk, to: to}, target_file)
       when tk in [:path, :module_path],
       do: to == target_file
  defp match_target_file(_item, _target_file), do: false

  defp counts_by_language(list) do
    list
    |> Enum.map(fn i -> i.language || "unknown" end)
    |> Enum.reduce(%{}, fn lang, acc -> Map.update(acc, lang, 1, &(&1 + 1)) end)
  end

  defp atoms_if_present(map) do
    map
    |> Enum.map(fn {k, v} -> {String.to_atom(k), normalize_filter_value(v)} end)
    |> Enum.into(%{})
  end

  defp normalize_filter_value(v) when is_binary(v) do
    case v do
      <<":"::utf8, rest::binary>> -> String.to_atom(rest)
      _ ->
        # try atom for the common enums; otherwise keep string
        down = String.downcase(v)
        case down do
          s when s in ["function", "class", "struct", "enum", "interface", "module", "symbol", "type", "impl", "macro"] -> String.to_atom(down)
          s when s in ["import", "export", "use", "aliases"] -> String.to_atom(down)
          s when s in ["module", "path", "module_path", "unknown"] -> String.to_atom(down)
          _ -> v
        end
    end
  end

  defp normalize_filter_value(v), do: v

  defp truthy?(v) when is_binary(v) do
    String.downcase(v) in ["1", "true", "yes", "on"]
  end

  defp truthy?(v) when is_boolean(v), do: v
  defp truthy?(_), do: false
end
