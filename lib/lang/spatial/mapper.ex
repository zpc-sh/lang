defmodule Lang.Spatial.Mapper do
  @moduledoc """
  Spatial navigation primitives (stubs).

  This module will host advanced spatial operations such as traverse, trace,
  and relations exploration. For now, it exposes placeholders to be wired into
  LSP or API layers when ready.
  """

  @type opts :: keyword()

  @doc """
  Plan a simple traversal through the codebase using latest map relations.

  Options:
  - :file - starting file path (required for now)
  - :depth - max depth (default: 3)
  - :language - optional language filter for relations
  Returns {:ok, %{start, depth, nodes, edges}}.
  """
  @spec traverse(String.t(), opts) :: {:ok, map()} | {:error, term()}
  def traverse(project_id, opts \\ []) when is_binary(project_id) do
    with {:ok, summary} <- Lang.Spatial.latest_map_summary(project_id) do
      start_file = Keyword.get(opts, :file)
      depth = Keyword.get(opts, :depth, 3)
      lang = Keyword.get(opts, :language)
      types = normalize_type_filters(Keyword.get(opts, :types))
      kinds = normalize_kind_filters(Keyword.get(opts, :kinds))

      if is_nil(start_file) do
        {:error, :missing_start_file}
      else
        edges = build_edges(summary.relations, lang, types)
        {visited, collected_edges} = bfs(edges, start_file, depth)

        nodes = Enum.map(visited, fn file -> %{file: file} end)

        symbols_by_file =
          if kinds == [] do
            %{}
          else
            build_symbols_by_file(summary.symbols, visited, kinds, lang)
          end

        result = %{
          start: start_file,
          depth: depth,
          nodes: nodes,
          edges: collected_edges,
          symbols: symbols_by_file
        }
        {:ok, result}
      end
    end
  end

  @doc """
  Trace shortest path across relations/calls between two files/targets.

  Spec map expects:
  - :from or "from" - starting node (file path or symbol ref)
  - :to or "to" - target node (file path or symbol ref)
  Options:
  - :language - limit traversal to relations of a given language
  """
  @spec trace_path(String.t(), map(), opts) :: {:ok, map()} | {:error, term()}
  def trace_path(project_id, spec, opts \\ []) when is_binary(project_id) and is_map(spec) do
    with {:ok, summary} <- Lang.Spatial.latest_map_summary(project_id) do
      from = Map.get(spec, :from) || Map.get(spec, "from")
      to = Map.get(spec, :to) || Map.get(spec, "to")
      lang = Keyword.get(opts, :language)
      types = normalize_type_filters(Keyword.get(opts, :types))

      cond do
        is_nil(from) or is_nil(to) -> {:error, :invalid_spec}
        true ->
          edges = build_edges(summary.relations, lang, types)
          case shortest_path(edges, from, to) do
            {:ok, nodes, edges_seq} ->
              {:ok, %{from: from, to: to, nodes: Enum.map(nodes, &%{file: &1}), edges: edges_seq}}

            {:error, :not_found} -> {:ok, %{from: from, to: to, nodes: [], edges: [], not_found: true}}
          end
      end
    end
  end

  @doc """
  Find related code artifacts (stub).
  """
  @spec find_related(String.t(), map(), opts) :: {:ok, map()} | {:error, term()}
  def find_related(project_id, criteria, opts \\ []) when is_binary(project_id) and is_map(criteria) do
    with {:ok, summary} <- Lang.Spatial.latest_map_summary(project_id) do
      file = Map.get(criteria, :file) || Map.get(criteria, "file")
      lang = Keyword.get(opts, :language)
      types = normalize_type_filters(Keyword.get(opts, :types))
      top_n = Keyword.get(opts, :top_n, 20)

      if is_nil(file) do
        {:error, :invalid_criteria}
      else
        edges = build_edges(summary.relations, lang, types)
        neighbors = Map.get(edges, file, []) |> Enum.map(& &1.to)

        counts =
          neighbors
          |> Enum.flat_map(fn n -> Map.get(edges, n, []) |> Enum.map(& &1.to) end)
          |> Enum.reject(&(&1 == file))
          |> Enum.frequencies()

        related =
          counts
          |> Enum.sort_by(fn {_node, c} -> -c end)
          |> Enum.take(top_n)
          |> Enum.map(fn {node, score} ->
            via = neighbors |> Enum.find(fn n -> Map.get(edges, n, []) |> Enum.any?(fn e -> e.to == node end) end)
            %{node: node, score: score, via: via}
          end)

        {:ok, %{file: file, related: related}}
      end
    end
  end

  # Internal helpers
  defp build_edges(relations, lang, types \\ nil) do
    allowed = MapSet.new(types || [])

    relations
    |> Enum.filter(fn r -> is_nil(lang) or r.language == lang end)
    |> Enum.filter(fn r ->
      if MapSet.size(allowed) == 0 do
        true
      else
        normalized = normalize_type(r.type)
        MapSet.member?(allowed, normalized)
      end
    end)
    |> Enum.group_by(& &1.from, fn r -> %{from: r.from, to: r.to, type: r.type, language: r.language, target_kind: r.target_kind} end)
  end

  defp bfs(edges, start, depth) do
    do_bfs(edges, depth, MapSet.new([start]), :queue.in({start, 0}, :queue.new()), MapSet.new(), [])
    |> then(fn {visited, _q, _seen_edges, collected} -> {MapSet.to_list(visited), Enum.reverse(collected)} end)
  end

  defp do_bfs(_edges, depth, visited, q, seen_edges, collected) do
    case :queue.out(q) do
      {{:value, {_node, d}}, q} when d < 0 -> {visited, q, seen_edges, collected}
      {{:value, {node, d}}, q} ->
        next_edges = Map.get(_edges, node, [])
        {visited, q, seen_edges, collected} =
          Enum.reduce(next_edges, {visited, q, seen_edges, collected}, fn e, {vst, qq, se, col} ->
            key = {e.from, e.to, e.type}
            col2 = if MapSet.member?(se, key), do: col, else: [e | col]
            se2 = MapSet.put(se, key)
            if MapSet.member?(vst, e.to) do
              {vst, qq, se2, col2}
            else
              {MapSet.put(vst, e.to), :queue.in({e.to, d + 1}, qq), se2, col2}
            end
          end)

        if d + 1 <= depth do
          do_bfs(_edges, depth, visited, q, seen_edges, collected)
        else
          {visited, q, seen_edges, collected}
        end

      {:empty, q} -> {visited, q, seen_edges, collected}
    end
  end

  defp shortest_path(edges, start, goal) do
    q = :queue.from_list([start])
    prev = %{start => nil}
    visited = MapSet.new([start])

    {found?, prev} =
      Stream.unfold(q, fn
        q ->
          case :queue.out(q) do
            {{:value, node}, q2} -> {{node, q2}, q2}
            {:empty, _} -> nil
          end
      end)
      |> Enum.reduce_while({false, prev, visited}, fn {node, q2}, {_found, prev_map, vis} ->
        if node == goal do
          {:halt, {true, prev_map, vis}}
        else
          neighbors = Map.get(edges, node, []) |> Enum.map(& &1.to)
          {vis2, q3, prev2} =
            Enum.reduce(neighbors, {vis, q2, prev_map}, fn n, {v, qacc, p} ->
              if MapSet.member?(v, n) do
                {v, qacc, p}
              else
                {MapSet.put(v, n), :queue.in(n, qacc), Map.put(p, n, node)}
              end
            end)

          {:cont, {false, prev2, vis2}}
        end
      end)

    case found? do
      true ->
        nodes = reconstruct_path(prev, goal)
        edge_seq = nodes |> Enum.chunk_every(2, 1, :discard) |> Enum.map(fn [a, b] -> pick_edge(edges, a, b) end) |> Enum.reject(&is_nil/1)
        {:ok, nodes, edge_seq}

      _ -> {:error, :not_found}
    end
  end

  defp reconstruct_path(prev, node, acc \\ []) do
    case Map.get(prev, node) do
      nil -> Enum.reverse([node | acc])
      parent -> reconstruct_path(prev, parent, [node | acc])
    end
  end

  defp pick_edge(edges, from, to) do
    Map.get(edges, from, []) |> Enum.find(fn e -> e.to == to end)
  end

  # Type normalization helpers
  defp normalize_type_filters(nil), do: nil
  defp normalize_type_filters(types) when is_list(types) do
    types |> Enum.map(&normalize_type/1) |> Enum.reject(&is_nil/1)
  end

  defp normalize_type_filters(types) when is_binary(types) do
    types
    |> String.split([",", " "], trim: true)
    |> Enum.map(&normalize_type/1)
    |> Enum.reject(&is_nil/1)
  end

  defp normalize_type(:imports), do: :import
  defp normalize_type("imports"), do: :import
  defp normalize_type(:import), do: :import
  defp normalize_type("import"), do: :import
  defp normalize_type(:uses), do: :use
  defp normalize_type("uses"), do: :use
  defp normalize_type(:use), do: :use
  defp normalize_type("use"), do: :use
  defp normalize_type(:aliases), do: :alias
  defp normalize_type("aliases"), do: :alias
  defp normalize_type(:alias), do: :alias
  defp normalize_type("alias"), do: :alias
  defp normalize_type(:export), do: :export
  defp normalize_type("export"), do: :export
  defp normalize_type(_), do: nil

  # Kind normalization helpers
  defp normalize_kind_filters(nil), do: []
  defp normalize_kind_filters(kinds) when is_list(kinds) do
    kinds
    |> Enum.map(fn k ->
      cond do
        is_atom(k) -> k
        is_binary(k) -> String.to_atom(k)
        true -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp normalize_kind_filters(kinds) when is_binary(kinds) do
    kinds
    |> String.split([",", " "], trim: true)
    |> Enum.map(&normalize_kind/1)
    |> Enum.reject(&is_nil/1)
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

  defp build_symbols_by_file(all_symbols, files, kinds, lang) do
    file_set = MapSet.new(files)

    all_symbols
    |> Enum.filter(fn s -> MapSet.member?(file_set, s.file) end)
    |> Enum.filter(fn s -> (kinds == [] or s.kind in kinds) and (is_nil(lang) or s.language == lang) end)
    |> Enum.group_by(& &1.file, fn s -> %{kind: s.kind, name: s.name, line: s.line, language: s.language} end)
  end
end
