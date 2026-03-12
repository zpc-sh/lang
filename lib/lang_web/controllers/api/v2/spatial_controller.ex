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

  @spatial_context "https://lang.nulity.com/context/spatial"

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
    with {:ok, summary} <- Lang.Spatial.latest_map_summary(project_id),
         {:ok, page} <- parse_positive_int_param(params, "page", @default_page),
         {:ok, page_size0} <- parse_positive_int_param(params, "page_size", @default_page_size) do
      section = Map.get(params, "section", "all")
      {page, page_size} = {page, min(page_size0, @max_page_size)}
      counts_only? = truthy?(Map.get(params, "counts_only"))

      languages = params |> Map.get("languages") |> parse_csv_list()

      types =
        params
        |> Map.get("types")
        |> parse_csv_list()
        |> Enum.map(&normalize_type/1)
        |> Enum.reject(&is_nil/1)

      kinds =
        params
        |> Map.get("kinds")
        |> parse_csv_list()
        |> Enum.map(&normalize_kind/1)
        |> Enum.reject(&is_nil/1)

      symbol_filters =
        Map.take(params, ["kind", "language", "file"])
        |> atoms_if_present()
        |> Map.put(:kinds, kinds)

      relation_filters =
        Map.take(params, ["type", "language", "target_kind", "from", "to", "file", "target_file"])
        |> atoms_if_present()
        |> Map.put(:types, types)

      # Symbols filtering, pagination, and counts
      {symbols_page, symbols_meta} =
        if section in ["all", "symbols"] do
          all_symbols = summary.symbols || []

          all_symbols =
            if languages == [],
              do: all_symbols,
              else: Enum.filter(all_symbols, &(&1.language in languages))

          filtered_symbols = Enum.filter(all_symbols, &filter_symbol(&1, symbol_filters))
          {page_items, meta} = paginate(filtered_symbols, page, page_size)

          %{
            total: length(filtered_symbols),
            total_all: length(all_symbols),
            page: page,
            page_size: page_size,
            counts_all_by_language: counts_by_language(all_symbols),
            counts_by_language: counts_by_language(filtered_symbols),
            counts_all_by_kind: counts_by_kind(all_symbols),
            counts_by_kind: counts_by_kind(filtered_symbols)
          }
          |> then(fn m -> {page_items, m} end)
        else
          {[],
           %{
             total: 0,
             total_all: 0,
             page: page,
             page_size: page_size,
             counts_all_by_language: %{},
             counts_by_language: %{},
             counts_all_by_kind: %{},
             counts_by_kind: %{}
           }}
        end

      # Relations filtering, pagination, and counts
      {relations_page, relations_meta} =
        if section in ["all", "relations"] do
          all_relations = summary.relations || []

          all_relations =
            if languages == [],
              do: all_relations,
              else: Enum.filter(all_relations, &(&1.language in languages))

          filtered_relations = Enum.filter(all_relations, &filter_relation(&1, relation_filters))
          {page_items, meta} = paginate(filtered_relations, page, page_size)

          %{
            total: length(filtered_relations),
            total_all: length(all_relations),
            page: page,
            page_size: page_size,
            counts_all_by_language: counts_by_language(all_relations),
            counts_by_language: counts_by_language(filtered_relations),
            counts_all_by_type: counts_by_type(all_relations),
            counts_by_type: counts_by_type(filtered_relations)
          }
          |> then(fn m -> {page_items, m} end)
        else
          {[],
           %{
             total: 0,
             total_all: 0,
             page: page,
             page_size: page_size,
             counts_all_by_language: %{},
             counts_by_language: %{},
             counts_all_by_type: %{},
             counts_by_type: %{}
           }}
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

      json(conn, maybe_with_context(conn, body))
    else
      {:error, :invalid_pagination} ->
        LangWeb.ApiError.json(conn, :bad_request, "invalid page or page_size")

      {:ok, nil} ->
        LangWeb.ApiError.json(conn, :not_found, "no map available")

      {:error, reason} ->
        Logger.error("map_summary failed", reason: inspect(reason))

        LangWeb.ApiError.json(conn, :internal_server_error, "internal_error", %{
          reason: inspect(reason)
        })
    end
  end

  @doc """
  GET /api/v2/spatial/trace_path/:project_id

  Query params: from (required), to (required), language (optional)
  Returns shortest path across relations.
  """
  def trace_path(conn, %{"project_id" => project_id} = params) do
    from = Map.get(params, "from")
    to = Map.get(params, "to")
    language = Map.get(params, "language")
    types = Map.get(params, "types")

    spec = %{from: from, to: to}
    opts = []
    opts = if language, do: Keyword.put(opts, :language, language), else: opts
    opts = if types, do: Keyword.put(opts, :types, types), else: opts

    case Lang.Spatial.Mapper.trace_path(project_id, spec, opts) do
      {:ok, result} ->
        json(conn, maybe_with_context(conn, result))

      {:error, :invalid_spec} ->
        LangWeb.ApiError.json(conn, :bad_request, "from and to are required")

      {:error, reason} ->
        LangWeb.ApiError.json(conn, :internal_server_error, "Internal error", %{
          reason: inspect(reason)
        })
    end
  end

  @doc """
  GET /api/v2/spatial/find_related/:project_id

  Query params: file (required), language (optional), types (optional list or csv), top_n
  Returns top related nodes by shared neighbors.
  """
  def find_related(conn, %{"project_id" => project_id} = params) do
    file = Map.get(params, "file")
    language = Map.get(params, "language")
    types = Map.get(params, "types")
    top_n = Map.get(params, "top_n")

    criteria = %{file: file}
    opts = []
    opts = if language, do: Keyword.put(opts, :language, language), else: opts
    opts = if types, do: Keyword.put(opts, :types, types), else: opts

    opts =
      case top_n do
        nil -> opts
        n when is_binary(n) -> Keyword.put(opts, :top_n, String.to_integer(n))
        n when is_integer(n) -> Keyword.put(opts, :top_n, n)
      end

    case Lang.Spatial.Mapper.find_related(project_id, criteria, opts) do
      {:ok, result} ->
        json(conn, maybe_with_context(conn, result))

      {:error, :invalid_criteria} ->
        LangWeb.ApiError.json(conn, :bad_request, "file is required")

      {:error, reason} ->
        LangWeb.ApiError.json(conn, :internal_server_error, "Internal error", %{
          reason: inspect(reason)
        })
    end
  end

  @doc """
  GET /api/v2/spatial/traverse/:project_id

  Query params: file (required), depth (default 3), language (optional), types (csv), kinds (csv)
  Returns traversal graph with optional per-file symbols filtered by kinds.
  """
  def traverse(conn, %{"project_id" => project_id} = params) do
    file = Map.get(params, "file")

    depth =
      case Map.get(params, "depth", "3") do
        val when is_integer(val) ->
          val

        val when is_binary(val) ->
          case Integer.parse(val) do
            {i, ""} -> i
            _ -> 3
          end

        _ ->
          3
      end

    language = Map.get(params, "language")
    types = Map.get(params, "types")
    kinds = Map.get(params, "kinds")

    opts = [depth: depth]
    opts = if file, do: Keyword.put(opts, :file, file), else: opts
    opts = if language, do: Keyword.put(opts, :language, language), else: opts
    opts = if types, do: Keyword.put(opts, :types, types), else: opts
    opts = if kinds, do: Keyword.put(opts, :kinds, kinds), else: opts

    case Lang.Spatial.Mapper.traverse(project_id, opts) do
      {:ok, result} ->
        json(conn, maybe_with_context(conn, result))

      {:error, :missing_start_file} ->
        LangWeb.ApiError.json(conn, :bad_request, "file is required")

      {:error, reason} ->
        LangWeb.ApiError.json(conn, :internal_server_error, "Internal error", %{
          reason: inspect(reason)
        })
    end
  end

  # Pagination helpers
  defp parse_positive_int_param(params, key, default) do
    case Map.get(params, key) do
      nil ->
        {:ok, default}

      val when is_integer(val) and val > 0 ->
        {:ok, val}

      val when is_binary(val) ->
        case Integer.parse(val) do
          {i, ""} when i > 0 -> {:ok, i}
          _ -> {:error, :invalid_pagination}
        end

      _ ->
        {:error, :invalid_pagination}
    end
  end

  defp paginate(list, page, page_size) do
    list = list || []
    offset = (page - 1) * page_size
    data = list |> Enum.drop(offset) |> Enum.take(page_size)
    {data, %{total: length(list), page: page, page_size: page_size}}
  end

  # Filtering
  defp filter_symbol(item, filters) do
    base = [
      eq_or_nil(item.kind, Map.get(filters, :kind)),
      eq_or_nil(item.language, Map.get(filters, :language)),
      eq_or_nil(item.file, Map.get(filters, :file))
    ]

    kind_membership_ok? =
      case Map.get(filters, :kinds) do
        [] -> true
        nil -> true
        list when is_list(list) -> item.kind in list
      end

    Enum.all?(base) and kind_membership_ok?
  end

  defp filter_relation(item, filters) do
    base = [
      eq_or_nil(item.type, Map.get(filters, :type)),
      eq_or_nil(item.language, Map.get(filters, :language)),
      eq_or_nil(item.target_kind, Map.get(filters, :target_kind)),
      eq_or_nil(item.from, Map.get(filters, :from)),
      # allow file= as alias for from
      eq_or_nil(item.from, Map.get(filters, :file) || Map.get(filters, :from)),
      eq_or_nil(item.to, Map.get(filters, :to)),
      match_target_file(item, Map.get(filters, :target_file))
    ]

    type_membership_ok? =
      case Map.get(filters, :types) do
        [] -> true
        nil -> true
        list when is_list(list) -> normalize_type(item.type) in list
      end

    Enum.all?(base) and type_membership_ok?
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

  defp counts_by_kind(list) do
    list
    |> Enum.map(fn i -> i.kind || :unknown end)
    |> Enum.reduce(%{}, fn k, acc -> Map.update(acc, k, 1, &(&1 + 1)) end)
  end

  defp counts_by_type(list) do
    list
    |> Enum.map(fn r -> normalize_type(r.type) || :unknown end)
    |> Enum.reduce(%{}, fn t, acc -> Map.update(acc, t, 1, &(&1 + 1)) end)
  end

  defp atoms_if_present(map) do
    map
    |> Enum.map(fn {k, v} -> {String.to_atom(k), normalize_filter_value(v)} end)
    |> Enum.into(%{})
  end

  defp normalize_filter_value(v) when is_binary(v) do
    case v do
      <<":"::utf8, rest::binary>> ->
        String.to_atom(rest)

      _ ->
        # try atom for the common enums; otherwise keep string
        down = String.downcase(v)

        case down do
          s
          when s in [
                 "function",
                 "class",
                 "struct",
                 "enum",
                 "interface",
                 "module",
                 "symbol",
                 "type",
                 "impl",
                 "macro"
               ] ->
            String.to_atom(down)

          s when s in ["import", "export", "use", "aliases"] ->
            String.to_atom(down)

          s when s in ["module", "path", "module_path", "unknown"] ->
            String.to_atom(down)

          _ ->
            v
        end
    end
  end

  defp normalize_filter_value(v), do: v

  defp parse_csv_list(nil), do: []

  defp parse_csv_list(val) when is_binary(val) do
    val
    |> String.split([",", " "], trim: true)
    |> Enum.reject(&(&1 == ""))
  end

  defp parse_csv_list(_), do: []

  defp normalize_type(v) when is_atom(v) do
    case v do
      :imports -> :import
      :uses -> :use
      :aliases -> :alias
      other -> other
    end
  end

  defp normalize_type(v) when is_binary(v) do
    case String.downcase(v) do
      "imports" -> :import
      "import" -> :import
      "uses" -> :use
      "use" -> :use
      "aliases" -> :alias
      "alias" -> :alias
      "export" -> :export
      _ -> nil
    end
  end

  defp normalize_kind(v) when is_binary(v) do
    case String.downcase(v) do
      "function" -> :function
      "class" -> :class
      "struct" -> :struct
      "enum" -> :enum
      "interface" -> :interface
      "module" -> :module
      "type" -> :type
      "impl" -> :impl
      "macro" -> :macro
      "symbol" -> :symbol
      _ -> nil
    end
  end

  defp truthy?(v) when is_binary(v) do
    String.downcase(v) in ["1", "true", "yes", "on"]
  end

  defp truthy?(v) when is_boolean(v), do: v
  defp truthy?(_), do: false

  defp maybe_with_context(conn, %{} = map) do
    if Phoenix.Controller.get_format(conn) == "jsonld" do
      Map.put_new(map, "@context", @spatial_context)
    else
      map
    end
  end

  defp maybe_with_context(_conn, other), do: other
end
