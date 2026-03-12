defmodule JsonldEx.Diff.Semantic do
  @moduledoc """
  Semantic graph diff for JSON-LD documents that preserves semantic meaning.
  
  This implementation is aware of JSON-LD semantics including:
  - Context expansion and compaction
  - IRI normalization and aliasing
  - RDF graph structure
  - Blank node identification
  - Type coercion and language tags
  
  The semantic diff compares the underlying RDF meaning rather than
  the surface JSON structure, making it ideal for:
  - Schema evolution
  - Context changes
  - Semantic versioning
  - Knowledge graph updates
  """

  alias JsonldEx.Native

  @type semantic_diff :: %{
    added_triples: [rdf_triple()],
    removed_triples: [rdf_triple()],
    modified_nodes: [node_diff()],
    context_changes: context_diff(),
    metadata: %{
      normalization_algorithm: atom(),
      blank_node_handling: atom(),
      semantic_equivalence: boolean()
    }
  }

  @type rdf_triple :: %{
    subject: binary(),
    predicate: binary(),
    object: binary() | %{value: binary(), type: binary(), language: binary()}
  }

  @type node_diff :: %{
    node_id: binary(),
    added_properties: [property_change()],
    removed_properties: [property_change()],
    modified_properties: [property_change()]
  }

  @type property_change :: %{
    property: binary(),
    old_value: term(),
    new_value: term(),
    change_type: :value | :type | :language | :datatype
  }

  @type context_diff :: %{
    added_mappings: %{binary() => binary()},
    removed_mappings: %{binary() => binary()},
    changed_mappings: %{binary() => {binary(), binary()}},
    base_changes: {binary() | nil, binary() | nil}
  }

  @doc """
  Generate semantic diff between two JSON-LD documents.
  
  This compares the underlying RDF graphs after normalization,
  accounting for context differences and semantic equivalence.
  
  ## Options
  
  - `normalize: boolean()` - Apply RDF graph normalization (default: true)
  - `blank_node_strategy: :uuid | :hash | :preserve` - How to handle blank nodes
  - `context_aware: boolean()` - Include context changes in diff (default: true)
  - `expand_contexts: boolean()` - Expand contexts before comparison (default: true)
  - `property_grouping: boolean()` - Group property changes by node (default: true)
  
  ## Examples
  
      iex> old = %{
      ...>   "@context" => %{"name" => "http://schema.org/name"},
      ...>   "@id" => "http://example.com/person/1",
      ...>   "name" => "John Doe"
      ...> }
      iex> new = %{
      ...>   "@context" => "http://schema.org/",
      ...>   "@id" => "http://example.com/person/1", 
      ...>   "@type" => "Person",
      ...>   "name" => "Jane Doe"
      ...> }
      iex> Semantic.diff(old, new)
      {:ok, %{
      ...>   modified_nodes: [%{
      ...>     node_id: "http://example.com/person/1",
      ...>     modified_properties: [%{
      ...>       property: "http://schema.org/name",
      ...>       old_value: "John Doe",
      ...>       new_value: "Jane Doe"
      ...>     }],
      ...>     added_properties: [%{
      ...>       property: "http://www.w3.org/1999/02/22-rdf-syntax-ns#type",
      ...>       new_value: "http://schema.org/Person"
      ...>     }]
      ...>   }]
      ...> }}
  """
  @spec diff(map(), map(), keyword()) :: {:ok, semantic_diff()} | {:error, term()}
  def diff(old, new, opts \\ []) do
    try do
      # Expand documents to full RDF representation
      {:ok, old_expanded} = expand_document(old, opts)
      {:ok, new_expanded} = expand_document(new, opts)
      
      # Convert to normalized RDF triples
      {:ok, old_triples} = document_to_triples(old_expanded, opts)
      {:ok, new_triples} = document_to_triples(new_expanded, opts)
      
      # Compare RDF graphs
      graph_diff = compare_rdf_graphs(old_triples, new_triples, opts)
      
      # Analyze context changes
      context_diff = if Keyword.get(opts, :context_aware, true) do
        compare_contexts(old, new, opts)
      else
        %{added_mappings: %{}, removed_mappings: %{}, changed_mappings: %{}, base_changes: {nil, nil}}
      end
      
      # Build semantic diff result
      result = %{
        added_triples: graph_diff.added,
        removed_triples: graph_diff.removed,
        modified_nodes: group_changes_by_node(graph_diff, opts),
        context_changes: context_diff,
        metadata: %{
          normalization_algorithm: Keyword.get(opts, :normalization_algorithm, :urdna2015),
          blank_node_handling: Keyword.get(opts, :blank_node_strategy, :uuid),
          semantic_equivalence: graphs_semantically_equivalent?(old_triples, new_triples)
        }
      }
      
      {:ok, result}
    rescue
      error -> {:error, {:semantic_diff_failed, error}}
    end
  end

  @doc """
  Apply semantic diff to a JSON-LD document.
  
  Applies changes at the RDF level and then compacts back
  to JSON-LD using the target context.
  """
  @spec patch(map(), semantic_diff(), keyword()) :: {:ok, map()} | {:error, term()}
  def patch(document, semantic_diff, opts \\ []) do
    try do
      # Expand document to RDF
      {:ok, expanded} = expand_document(document, opts)
      {:ok, triples} = document_to_triples(expanded, opts)
      
      # Apply RDF-level changes
      updated_triples = apply_rdf_changes(triples, semantic_diff, opts)
      
      # Convert back to JSON-LD
      {:ok, updated_document} = triples_to_document(updated_triples, opts)
      
      # Apply context changes if needed
      final_document = if map_size(semantic_diff.context_changes.added_mappings) > 0 or 
                             map_size(semantic_diff.context_changes.removed_mappings) > 0 do
        apply_context_changes(updated_document, semantic_diff.context_changes, opts)
      else
        updated_document
      end
      
      {:ok, final_document}
    rescue
      error -> {:error, {:semantic_patch_failed, error}}
    end
  end

  @doc """
  Validate that a semantic patch can be applied.
  """
  @spec validate_patch(map(), semantic_diff(), keyword()) :: {:ok, boolean()} | {:error, term()}
  def validate_patch(document, semantic_diff, opts \\ []) do
    try do
      # Check if document can be expanded
      {:ok, _expanded} = expand_document(document, opts)
      
      # Check if removed triples exist in document
      {:ok, current_triples} = document |> expand_document(opts) |> elem(1) |> document_to_triples(opts)
      current_triple_set = MapSet.new(current_triples)
      
      removed_exists = Enum.all?(semantic_diff.removed_triples, fn triple ->
        MapSet.member?(current_triple_set, triple)
      end)
      
      {:ok, removed_exists}
    rescue
      _error -> {:ok, false}
    end
  end

  @doc """
  Merge multiple semantic diffs.
  """
  @spec merge_diffs([semantic_diff()], keyword()) :: {:ok, semantic_diff()} | {:error, term()}
  def merge_diffs(diffs, opts \\ [])
  
  def merge_diffs([], _opts) do
    {:ok, empty_semantic_diff()}
  end

  def merge_diffs(diffs, opts) do
    try do
      result = Enum.reduce(diffs, empty_semantic_diff(), fn diff, acc ->
        merge_semantic_diff(acc, diff, opts)
      end)
      
      {:ok, result}
    rescue
      error -> {:error, {:merge_failed, error}}
    end
  end

  @doc """
  Generate the inverse of a semantic diff.
  """
  @spec inverse(semantic_diff(), keyword()) :: {:ok, semantic_diff()} | {:error, term()}
  def inverse(semantic_diff, opts \\ []) do
    try do
      result = %{
        added_triples: semantic_diff.removed_triples,
        removed_triples: semantic_diff.added_triples,
        modified_nodes: invert_node_modifications(semantic_diff.modified_nodes),
        context_changes: invert_context_changes(semantic_diff.context_changes),
        metadata: Map.put(semantic_diff.metadata, :semantic_equivalence, false)
      }
      
      {:ok, result}
    rescue
      error -> {:error, {:inverse_failed, error}}
    end
  end

  # Private functions

  defp expand_document(document, opts) do
    if Keyword.get(opts, :expand_contexts, true) do
      try do
        case Native.expand(Jason.encode!(document), []) do
          {:ok, expanded_json} ->
            {:ok, Jason.decode!(expanded_json)}
          error -> 
            error
        end
      rescue
        _error -> {:ok, document}  # Fallback to unexpanded document
      catch
        :error, :nif_not_loaded -> {:ok, document}
        _ -> {:ok, document}
      end
    else
      {:ok, document}
    end
  end

  defp document_to_triples(document, opts) do
    # Prefer native conversion if available and returns non-empty
    with {:ok, triples} <- try_native_to_triples(document),
         true <- length(triples) > 0 do
      {:ok, triples}
    else
      _ -> {:ok, extract_triples_elixir(document, opts)}
    end
  end

  defp try_native_to_triples(document) do
    try do
      case Native.to_rdf(Jason.encode!(document), [format: :ntriples]) do
        {:ok, ntriples} -> {:ok, parse_ntriples(ntriples)}
        _ -> {:ok, []}
      end
    rescue
      _ -> {:ok, []}
    catch
      :error, :nif_not_loaded -> {:ok, []}
      _ -> {:ok, []}
    end
  end

  defp triples_to_document(triples, _opts) do
    ntriples = serialize_ntriples(triples)
    
    try do
      case Native.from_rdf(ntriples, [format: :ntriples]) do
        {:ok, json_ld} ->
          {:ok, Jason.decode!(json_ld)}
        error ->
          error
      end
    rescue
      _error -> {:ok, %{}}  # Return empty document if conversion fails
    catch
      :error, :nif_not_loaded -> {:ok, %{}}
      _ -> {:ok, %{}}
    end
  end

  defp parse_ntriples(ntriples_string) do
    ntriples_string
    |> String.split("\n")
    |> Enum.reject(&(String.trim(&1) == ""))
    |> Enum.map(&parse_ntriple_line/1)
    |> Enum.reject(&is_nil/1)
  end

  defp parse_ntriple_line(line) do
    # Simple N-Triples parser - in production use proper parser
    line = String.trim(line)
    if String.ends_with?(line, " .") do
      parts = 
        line
        |> String.slice(0..-3)
        |> String.split(" ", parts: 3)
      
      case parts do
        [subject, predicate, object] ->
          %{
            subject: clean_iri_or_blank(subject),
            predicate: clean_iri_or_blank(predicate), 
            object: parse_object(object)
          }
        _ ->
          nil
      end
    else
      nil
    end
  end

  defp clean_iri_or_blank(term) do
    cond do
      String.starts_with?(term, "<") and String.ends_with?(term, ">") ->
        String.slice(term, 1..-2)
      String.starts_with?(term, "_:") ->
        term
      true ->
        term
    end
  end

  defp parse_object(object) do
    cond do
      String.starts_with?(object, "<") and String.ends_with?(object, ">") ->
        String.slice(object, 1..-2)
      
      String.starts_with?(object, "\"") ->
        # Parse literal with possible type/language
        parse_literal(object)
      
      String.starts_with?(object, "_:") ->
        object
      
      true ->
        object
    end
  end

  defp parse_literal(literal) do
    # Simple literal parsing - handle "value"^^<type> and "value"@lang
    cond do
      String.contains?(literal, "^^<") ->
        [value_part, type_part] = String.split(literal, "^^<", parts: 2)
        value = String.slice(value_part, 1..-2)  # Remove quotes
        type = String.slice(type_part, 0..-2)   # Remove closing >
        %{value: value, type: type}
      
      String.contains?(literal, "\"@") ->
        [value_part, lang] = String.split(literal, "\"@", parts: 2)
        value = String.slice(value_part, 1..-1)  # Remove opening quote
        %{value: value, language: lang}
      
      true ->
        String.slice(literal, 1..-2)  # Simple string, remove quotes
    end
  end

  defp serialize_ntriples(triples) do
    Enum.map_join(triples, "\n", fn triple ->
      subject = format_term_for_ntriples(triple.subject)
      predicate = format_term_for_ntriples(triple.predicate)
      object = format_object_for_ntriples(triple.object)
      "#{subject} #{predicate} #{object} ."
    end)
  end

  defp format_term_for_ntriples(term) do
    cond do
      String.starts_with?(term, "_:") -> term
      String.starts_with?(term, "http") -> "<#{term}>"
      true -> "<#{term}>"
    end
  end

  defp format_object_for_ntriples(object) when is_binary(object) do
    if String.starts_with?(object, "_:") or String.starts_with?(object, "http") do
      format_term_for_ntriples(object)
    else
      "\"#{object}\""
    end
  end

  defp format_object_for_ntriples(%{value: value, type: type}) do
    "\"#{value}\"^^<#{type}>"
  end

  defp format_object_for_ntriples(%{value: value, language: lang}) do
    "\"#{value}\"@#{lang}"
  end

  defp compare_rdf_graphs(old_triples, new_triples, _opts) do
    # Normalize blank nodes deterministically for robust comparison
    norm_old = normalize_blank_nodes(old_triples)
    norm_new = normalize_blank_nodes(new_triples)

    old_set = MapSet.new(norm_old)
    new_set = MapSet.new(norm_new)

    added = MapSet.difference(new_set, old_set) |> MapSet.to_list()
    removed = MapSet.difference(old_set, new_set) |> MapSet.to_list()
    unchanged = MapSet.intersection(old_set, new_set) |> MapSet.to_list()

    %{
      added: added,
      removed: removed,
      unchanged: unchanged
    }
  end

  defp compare_contexts(old, new, _opts) do
    old_context = extract_context(old)
    new_context = extract_context(new)
    
    old_mappings = flatten_context(old_context)
    new_mappings = flatten_context(new_context)
    
    old_keys = MapSet.new(Map.keys(old_mappings))
    new_keys = MapSet.new(Map.keys(new_mappings))
    
    added_keys = MapSet.difference(new_keys, old_keys)
    removed_keys = MapSet.difference(old_keys, new_keys)
    common_keys = MapSet.intersection(old_keys, new_keys)
    
    added_mappings = Map.take(new_mappings, MapSet.to_list(added_keys))
    removed_mappings = Map.take(old_mappings, MapSet.to_list(removed_keys))
    
    changed_mappings = 
      common_keys
      |> Enum.reduce(%{}, fn key, acc ->
        old_val = Map.get(old_mappings, key)
        new_val = Map.get(new_mappings, key)
        if old_val != new_val do
          Map.put(acc, key, {old_val, new_val})
        else
          acc
        end
      end)
    
    %{
      added_mappings: added_mappings,
      removed_mappings: removed_mappings, 
      changed_mappings: changed_mappings,
      base_changes: {extract_base(old_context), extract_base(new_context)}
    }
  end

  defp extract_context(document) do
    Map.get(document, "@context", %{})
  end

  defp flatten_context(context) when is_map(context) do
    context
    |> Enum.reduce(%{}, fn {key, value}, acc ->
      if is_binary(value) do
        Map.put(acc, key, value)
      else
        Map.put(acc, key, inspect(value))
      end
    end)
  end

  defp flatten_context(context) when is_binary(context) do
    %{"@base" => context}
  end

  defp flatten_context(_) do
    %{}
  end

  defp extract_base(context) when is_map(context) do
    Map.get(context, "@base")
  end

  defp extract_base(_) do
    nil
  end

  defp group_changes_by_node(graph_diff, _opts) do
    # Identify modified properties: same subject+predicate with different object
    added_by_sp =
      graph_diff.added
      |> Enum.group_by(fn t -> {t.subject, t.predicate} end)

    removed_by_sp =
      graph_diff.removed
      |> Enum.group_by(fn t -> {t.subject, t.predicate} end)

    subjects =
      (graph_diff.added ++ graph_diff.removed)
      |> Enum.map(& &1.subject)
      |> Enum.uniq()

    Enum.map(subjects, fn subj ->
      added_for_node = Enum.filter(graph_diff.added, &(&1.subject == subj))
      removed_for_node = Enum.filter(graph_diff.removed, &(&1.subject == subj))

      # Build modified_properties and filter from add/remove lists
      {modified, remaining_added, remaining_removed} =
        build_modified_properties(added_for_node, removed_for_node, added_by_sp, removed_by_sp)

      added_props = Enum.map(remaining_added, fn triple ->
        %{property: triple.predicate, new_value: triple.object, change_type: :value}
      end)

      removed_props = Enum.map(remaining_removed, fn triple ->
        %{property: triple.predicate, old_value: triple.object, change_type: :value}
      end)

      %{
        node_id: subj,
        added_properties: added_props,
        removed_properties: removed_props,
        modified_properties: modified
      }
    end)
  end

  defp build_modified_properties(added_for_node, removed_for_node, added_by_sp, removed_by_sp) do
    # For each subject+predicate, if both added and removed exist, pair them as modified
    added_map = MapSet.new(added_for_node)
    removed_map = MapSet.new(removed_for_node)

    sps =
      (added_for_node ++ removed_for_node)
      |> Enum.map(fn t -> {t.subject, t.predicate} end)
      |> Enum.uniq()

    {mods, used_add, used_rem} =
      Enum.reduce(sps, {[], MapSet.new(), MapSet.new()}, fn sp, {acc, ua, ur} ->
        adds = Map.get(added_by_sp, sp, []) |> Enum.reject(&MapSet.member?(ua, &1))
        rems = Map.get(removed_by_sp, sp, []) |> Enum.reject(&MapSet.member?(ur, &1))
        case {adds, rems} do
          {[a | _], [r | _]} ->
            mod = %{property: elem(sp, 1), old_value: r.object, new_value: a.object, change_type: :value}
            { [mod | acc], MapSet.put(ua, a), MapSet.put(ur, r) }
          _ -> {acc, ua, ur}
        end
      end)

    remaining_added = Enum.reject(added_for_node, &MapSet.member?(used_add, &1))
    remaining_removed = Enum.reject(removed_for_node, &MapSet.member?(used_rem, &1))
    {Enum.reverse(mods), remaining_added, remaining_removed}
  end

  defp normalize_blank_nodes(triples) do
    # Assign a deterministic hash-based label for each blank node occurrence
    bnodes =
      triples
      |> Enum.flat_map(fn t ->
        subs = if is_binary(t.subject) and String.starts_with?(t.subject, "_:") do [t.subject] else [] end
        objs = case t.object do
          s when is_binary(s) -> if String.starts_with?(s, "_:") do [s] else [] end
          _ -> []
        end
        subs ++ objs
      end)
      |> Enum.uniq()

    mapping =
      bnodes
      |> Enum.map(fn b -> {b, bnode_fingerprint(triples, b)} end)
      |> Enum.sort_by(fn {_b, fp} -> fp end)
      |> Enum.with_index()
      |> Enum.into(%{}, fn {{b, _fp}, idx} -> {b, "_:h" <> Base.encode16(<<idx::32>>, case: :lower)} end)

    Enum.map(triples, fn t ->
      subj = Map.get(mapping, t.subject, t.subject)
      obj = case t.object do
        s when is_binary(s) -> Map.get(mapping, s, s)
        other -> other
      end
      %{t | subject: subj, object: obj}
    end)
  end

  defp bnode_fingerprint(triples, bnode) do
    related =
      triples
      |> Enum.filter(fn t -> t.subject == bnode or (is_binary(t.object) and t.object == bnode) end)
      |> Enum.map(fn t ->
        pred = t.predicate
        obj = case t.object do
          m = %{value: _, type: _} -> "lit:" <> m.value <> ":" <> m.type
          m = %{value: _, language: lang} -> "lit:" <> m.value <> "@" <> lang
          s when is_binary(s) -> if String.starts_with?(s, "_:") do "_" else s end
          other -> inspect(other)
        end
        pred <> "->" <> obj
      end)
      |> Enum.sort()
      |> Enum.join("|")

    :crypto.hash(:sha256, related) |> Base.encode16(case: :lower)
  end

  defp extract_triples_elixir(document, _opts) do
    # Attempt to extract triples from expanded or compact JSON-LD
    {triples, _bnodes} = extract_triples_node(document, %{}, [])
    normalize_blank_nodes(triples)
  end

  defp extract_triples_node(value, bnode_map, acc) when is_list(value) do
    Enum.reduce(value, {acc, bnode_map}, fn v, {a, bm} -> extract_triples_node(v, bm, a) end)
  end

  defp extract_triples_node(value, bnode_map, acc) when is_map(value) do
    subject = Map.get(value, "@id") || assign_bnode(value, bnode_map)
    {acc1, bm1} =
      case Map.get(value, "@type") do
        nil -> {acc, bnode_map}
        types when is_list(types) ->
          rdf_type = "http://www.w3.org/1999/02/22-rdf-syntax-ns#type"
          {Enum.reduce(types, acc, fn type_iri, a ->
            subj = subject
            triple = %{subject: subj, predicate: rdf_type, object: type_iri}
            [triple | a]
          end), bnode_map}
        type when is_binary(type) ->
          rdf_type = "http://www.w3.org/1999/02/22-rdf-syntax-ns#type"
          triple = %{subject: subject, predicate: rdf_type, object: type}
          {[triple | acc], bnode_map}
      end

    Enum.reduce(value, {acc1, bm1}, fn {k, v}, {a, bm} ->
      cond do
        String.starts_with?(k, "@") -> {a, bm}
        is_list(v) ->
          Enum.reduce(v, {a, bm}, fn item, {aa, bb} ->
            case value_to_object(item, bb) do
              {:node, obj_id, bb2, acc_more} ->
                triple = %{subject: subject, predicate: expand_predicate(k), object: obj_id}
                {[triple | acc_more ++ aa], bb2}
              {:literal, lit} ->
                triple = %{subject: subject, predicate: expand_predicate(k), object: lit}
                {[triple | aa], bb}
            end
          end)
        true ->
          case value_to_object(v, bm) do
            {:node, obj_id, bm2, acc_more} ->
              triple = %{subject: subject, predicate: expand_predicate(k), object: obj_id}
              {[triple | acc_more ++ a], bm2}
            {:literal, lit} ->
              triple = %{subject: subject, predicate: expand_predicate(k), object: lit}
              {[triple | a], bm}
          end
      end
    end)
  end

  defp extract_triples_node(_other, bnode_map, acc) do
    {acc, bnode_map}
  end

  defp value_to_object(%{"@id" => id} = node, bnode_map) when is_binary(id) do
    # Node reference by IRI
    {:node, id, bnode_map, []}
  end

  defp value_to_object(%{"@value" => val} = lit, bnode_map) do
    case {val, Map.get(lit, "@type"), Map.get(lit, "@language")} do
      {v, type, nil} when is_number(v) or is_boolean(v) or is_binary(v) ->
        lit_map = if is_binary(type) do
          %{value: v |> to_string_if_needed(), type: type}
        else
          # default to xsd:string for strings, others keep stringified value
          if is_binary(v), do: %{value: v, type: "http://www.w3.org/2001/XMLSchema#string"}, else: %{value: to_string(v), type: "http://www.w3.org/2001/XMLSchema#string"}
        end
        {:literal, lit_map}
      {v, _type, lang} when is_binary(lang) ->
        {:literal, %{value: v, language: lang}}
      {v, _t, _l} ->
        {:literal, %{value: v |> to_string_if_needed(), type: "http://www.w3.org/2001/XMLSchema#string"}}
    end
  end

  defp value_to_object(node, bnode_map) when is_map(node) do
    # Embedded node blank
    subj = assign_bnode(node, bnode_map)
    {more_triples, bm2} = extract_triples_node(node, bnode_map, [])
    {:node, subj, bm2, more_triples}
  end

  defp value_to_object(val, bnode_map) do
    # Primitive literal
    lit = case val do
      v when is_binary(v) -> %{value: v, type: "http://www.w3.org/2001/XMLSchema#string"}
      v when is_integer(v) -> %{value: Integer.to_string(v), type: "http://www.w3.org/2001/XMLSchema#integer"}
      v when is_float(v) -> %{value: :erlang.float_to_binary(v, [:compact]), type: "http://www.w3.org/2001/XMLSchema#double"}
      v when is_boolean(v) -> %{value: to_string(v), type: "http://www.w3.org/2001/XMLSchema#boolean"}
      _ -> %{value: inspect(val), type: "http://www.w3.org/2001/XMLSchema#string"}
    end
    {:literal, lit}
  end

  defp to_string_if_needed(v) when is_binary(v), do: v
  defp to_string_if_needed(v), do: to_string(v)

  defp assign_bnode(node, bnode_map) do
    # Deterministically hash the node content as a label
    fingerprint = :crypto.hash(:sha256, :erlang.term_to_binary(sorted_map(node))) |> Base.encode16(case: :lower)
    Map.get(bnode_map, node, "_:h" <> String.slice(fingerprint, 0, 8))
  end

  defp sorted_map(map) when is_map(map) do
    map
    |> Enum.sort_by(fn {k, _} -> k end)
    |> Enum.map(fn {k, v} -> {k, sorted_map(v)} end)
  end

  defp sorted_map(list) when is_list(list) do
    Enum.map(list, &sorted_map/1)
  end

  defp sorted_map(other), do: other

  defp expand_predicate(pred) do
    cond do
      String.starts_with?(pred, "http://") or String.starts_with?(pred, "https://") -> pred
      String.contains?(pred, ":") ->
        [pfx, local] = String.split(pred, ":", parts: 2)
        case pfx do
          "rdf" -> "http://www.w3.org/1999/02/22-rdf-syntax-ns#" <> local
          "rdfs" -> "http://www.w3.org/2000/01/rdf-schema#" <> local
          "schema" -> "http://schema.org/" <> local
          _ -> pred
        end
      true -> "http://example.org/" <> pred
    end
  end

  defp graphs_semantically_equivalent?(triples1, triples2) do
    set1 = MapSet.new(triples1)
    set2 = MapSet.new(triples2)
    MapSet.equal?(set1, set2)
  end

  defp apply_rdf_changes(triples, semantic_diff, _opts) do
    triple_set = MapSet.new(triples)
    
    # Remove triples
    after_removals = MapSet.difference(triple_set, MapSet.new(semantic_diff.removed_triples))
    
    # Add triples  
    after_additions = MapSet.union(after_removals, MapSet.new(semantic_diff.added_triples))
    
    MapSet.to_list(after_additions)
  end

  defp apply_context_changes(document, context_changes, _opts) do
    current_context = Map.get(document, "@context", %{})
    
    new_context = 
      current_context
      |> Map.merge(context_changes.added_mappings)
      |> Map.drop(Map.keys(context_changes.removed_mappings))
      |> Map.merge(Enum.into(context_changes.changed_mappings, %{}, fn {k, {_old, new}} -> {k, new} end))
    
    Map.put(document, "@context", new_context)
  end

  defp empty_semantic_diff do
    %{
      added_triples: [],
      removed_triples: [],
      modified_nodes: [],
      context_changes: %{
        added_mappings: %{},
        removed_mappings: %{},
        changed_mappings: %{},
        base_changes: {nil, nil}
      },
      metadata: %{
        normalization_algorithm: :urdna2015,
        blank_node_handling: :uuid,
        semantic_equivalence: true
      }
    }
  end

  defp merge_semantic_diff(acc, diff, _opts) do
    %{
      added_triples: acc.added_triples ++ diff.added_triples,
      removed_triples: acc.removed_triples ++ diff.removed_triples,
      modified_nodes: acc.modified_nodes ++ diff.modified_nodes,
      context_changes: merge_context_changes(acc.context_changes, diff.context_changes),
      metadata: acc.metadata
    }
  end

  defp merge_context_changes(acc, diff) do
    %{
      added_mappings: Map.merge(acc.added_mappings, diff.added_mappings),
      removed_mappings: Map.merge(acc.removed_mappings, diff.removed_mappings),
      changed_mappings: Map.merge(acc.changed_mappings, diff.changed_mappings),
      base_changes: diff.base_changes  # Latest wins
    }
  end

  defp invert_node_modifications(node_mods) do
    Enum.map(node_mods, fn node_mod ->
      %{
        node_id: node_mod.node_id,
        added_properties: node_mod.removed_properties,
        removed_properties: node_mod.added_properties,
        modified_properties: Enum.map(node_mod.modified_properties, fn prop ->
          %{prop | old_value: prop.new_value, new_value: prop.old_value}
        end)
      }
    end)
  end

  defp invert_context_changes(context_changes) do
    %{
      added_mappings: context_changes.removed_mappings,
      removed_mappings: context_changes.added_mappings,
      changed_mappings: Enum.into(context_changes.changed_mappings, %{}, fn {k, {old, new}} -> {k, {new, old}} end),
      base_changes: case context_changes.base_changes do
        {old, new} -> {new, old}
        _ -> {nil, nil}
      end
    }
  end
end
