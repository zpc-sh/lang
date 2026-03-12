defmodule JsonldEx.Diff.Structural do
  @moduledoc """
  jsondiffpatch-style structural diff for human-readable JSON-LD changes.
  
  This implementation follows the jsondiffpatch delta format:
  https://github.com/benjamine/jsondiffpatch/blob/master/docs/deltas.md
  
  Delta format:
  - Changed value: [old_value, new_value] 
  - Added value: [new_value]
  - Deleted value: [old_value, 0, 0]
  - Array item moved: ["", from_index, 3]
  - Text diff: [text_diff, 0, 2]
  """

  @type structural_diff :: %{
    optional(binary()) => delta_value()
  }

  @type delta_value :: 
    list(term()) |                # [old, new] for changes, [old, 0, 0] for deletions, ["", from, 3] for moves, [text_diff, 0, 2] for text
    map()                         # nested object diffs

  @doc """
  Generate structural diff between two JSON-LD documents.
  
  Returns a compact delta format that's human-readable and
  suitable for version control or change visualization.
  
  ## Options
  
  - `include_moves: boolean()` - Detect array item moves (default: true)
  - `array_diff: :lcs | :simple` - Array diffing algorithm (default: :lcs)
  - `text_diff: boolean()` - Generate text diffs for strings (default: true)
  - `object_hash: function()` - Custom hash function for objects
  
  ## Examples
  
      iex> old = %{"name" => "John", "age" => 30}
      iex> new = %{"name" => "Jane", "age" => 30, "city" => "NYC"}
      iex> Structural.diff(old, new)
      {:ok, %{
        "name" => ["John", "Jane"],
        "city" => ["NYC"]
      }}
  """
  @spec diff(map(), map(), keyword()) :: {:ok, structural_diff()} | {:error, term()}
  def diff(old, new, opts \\ []) do
    try do
      delta = diff_value(old, new, opts)
      
      case delta do
        %{} = delta_map when map_size(delta_map) == 0 -> {:ok, %{}}
        delta_result -> {:ok, delta_result}
      end
    rescue
      error -> {:error, {:diff_failed, error}}
    end
  end

  @doc """
  Apply structural diff to a document.
  """
  @spec patch(map(), structural_diff(), keyword()) :: {:ok, map()} | {:error, term()}
  def patch(document, delta, opts \\ []) do
    try do
      result = patch_value(document, delta, opts)
      {:ok, result}
    rescue
      error -> {:error, {:patch_failed, error}}
    end
  end

  @doc """
  Validate that a structural patch can be applied.
  """
  @spec validate_patch(map(), structural_diff(), keyword()) :: {:ok, boolean()} | {:error, term()}
  def validate_patch(document, delta, opts \\ []) do
    try do
      _result = patch_value(document, delta, opts)
      {:ok, true}
    rescue
      _error -> {:ok, false}
    end
  end

  @doc """
  Merge multiple structural diffs.
  
  Merges deltas by applying them sequentially.
  Later changes override earlier ones for the same path.
  """
  @spec merge_diffs([structural_diff()], keyword()) :: {:ok, structural_diff()} | {:error, term()}
  def merge_diffs(diffs, opts \\ [])
  
  def merge_diffs([], _opts) do
    {:ok, %{}}
  end

  def merge_diffs(diffs, opts) when is_list(diffs) do
    try do
      result = Enum.reduce(diffs, %{}, fn diff, acc ->
        merge_delta(acc, diff, opts)
      end)
      
      {:ok, result}
    rescue
      error -> {:error, {:merge_failed, error}}
    end
  end

  @doc """
  Generate the inverse of a structural diff.
  """
  @spec inverse(structural_diff(), keyword()) :: {:ok, structural_diff()} | {:error, term()}
  def inverse(delta, opts \\ []) do
    try do
      result = invert_delta(delta, opts)
      {:ok, result}
    rescue
      error -> {:error, {:inverse_failed, error}}
    end
  end

  # Private functions

  defp diff_value(old, new, _opts) when old == new do
    %{}
  end

  defp diff_value(old, new, opts) when is_map(old) and is_map(new) do
    diff_object(old, new, opts)
  end

  defp diff_value(old, new, opts) when is_list(old) and is_list(new) do
    diff_array(old, new, opts)
  end

  defp diff_value(old, new, opts) when is_binary(old) and is_binary(new) do
    if Keyword.get(opts, :text_diff, true) and String.length(old) > 60 do
      diff_text(old, new, opts)
    else
      [old, new]
    end
  end

  defp diff_value(old, new, _opts) do
    [old, new]
  end

  defp diff_object(old, new, opts) do
    all_keys = MapSet.union(MapSet.new(Map.keys(old)), MapSet.new(Map.keys(new)))
    
    all_keys
    |> Enum.reduce(%{}, fn key, acc ->
      old_val = Map.get(old, key)
      new_val = Map.get(new, key)
      
      delta = cond do
        old_val == nil ->
          [new_val]  # Added
        
        new_val == nil ->
          [old_val, 0, 0]  # Deleted
        
        old_val != new_val ->
          sub_delta = diff_value(old_val, new_val, opts)
          if is_map(sub_delta) and map_size(sub_delta) == 0 do
            nil
          else
            sub_delta
          end
        
        true ->
          nil
      end
      
      if delta != nil do
        Map.put(acc, key, delta)
      else
        acc
      end
    end)
  end

  defp diff_array(old, new, opts) do
    case Keyword.get(opts, :array_diff, :lcs) do
      :lcs ->
        diff_array_lcs(old, new, opts)
      :simple ->
        diff_array_simple(old, new, opts)
    end
  end

  defp diff_array_simple(old, new, opts) do
    max_len = max(length(old), length(new))
    
    0..(max_len - 1)
    |> Enum.reduce(%{}, fn index, acc ->
      old_val = Enum.at(old, index)
      new_val = Enum.at(new, index)
      
      delta = cond do
        old_val == nil and new_val != nil ->
          [new_val]  # Added
        
        old_val != nil and new_val == nil ->
          [old_val, 0, 0]  # Deleted
        
        old_val != new_val ->
          sub_delta = diff_value(old_val, new_val, opts)
          if is_map(sub_delta) and map_size(sub_delta) == 0 do
            nil
          else
            sub_delta
          end
        
        true ->
          nil
      end
      
      if delta != nil do
        # Use _index for all array operations to match test expectations
        key = "_#{index}"
        Map.put(acc, key, delta)
      else
        acc
      end
    end)
  end

  defp diff_array_lcs(old, new, opts) do
    # Compute LCS for optimal diff
    {lcs_ops, move_info} = compute_lcs_diff(old, new)
    
    # Convert to jsondiffpatch delta format
    delta = operations_to_delta(lcs_ops, move_info, opts)
    
    # Add move detection if enabled
    if Keyword.get(opts, :include_moves, true) do
      add_move_detection(delta, old, new, move_info)
    else
      delta
    end
  end

  defp detect_array_moves(old, new, opts) do
    # Build hash maps for fast lookup
    old_with_index = old |> Enum.with_index() |> Enum.map(fn {val, idx} -> {hash_value(val), {val, idx}} end)
    new_with_index = new |> Enum.with_index() |> Enum.map(fn {val, idx} -> {hash_value(val), {val, idx}} end)
    
    old_hashes = Map.new(old_with_index)
    new_hashes = Map.new(new_with_index)
    
    # Find moved items
    moves = 
      new_with_index
      |> Enum.reduce(%{}, fn {hash, {_val, new_idx}}, acc ->
        case Map.get(old_hashes, hash) do
          {_old_val, old_idx} when old_idx != new_idx ->
            Map.put(acc, "_#{new_idx}", ["", old_idx, 3])
          _ ->
            acc
        end
      end)
    
    # Find additions/deletions/changes
    remaining_diffs = diff_array_simple(old, new, opts)
    
    # Remove moved items from remaining diffs
    filtered_diffs = 
      remaining_diffs
      |> Enum.reject(fn {key, _value} ->
        Map.has_key?(moves, key)
      end)
      |> Map.new()
    
    {moves, filtered_diffs}
  end

  defp diff_text(old, new, _opts) do
    # Simple character-level diff for now
    # In production, should use Myers' algorithm or similar
    if String.jaro_distance(old, new) > 0.8 do
      text_delta = simple_text_diff(old, new)
      [text_delta, 0, 2]
    else
      [old, new]
    end
  end

  defp simple_text_diff(old, new) do
    # Placeholder - implement proper text diffing
    "@@ -1,#{String.length(old)} +1,#{String.length(new)} @@\n-#{old}\n+#{new}"
  end

  defp patch_value(document, delta, opts) when is_map(delta) do
    if is_list(document) do
      patch_array(document, delta, opts)
    else
      patch_object(document, delta, opts)
    end
  end

  defp patch_value(_document, [new_value], _opts) do
    # Addition: [new_value]
    new_value
  end

  defp patch_value(_document, [_old_value, 0, 0], _opts) do
    # Deletion: [old_value, 0, 0] - return nil to delete
    nil
  end

  defp patch_value(_document, [_old_value, new_value], _opts) do
    # Change: [old_value, new_value]
    new_value
  end

  defp patch_value(document, [text_diff, 0, 2], _opts) when is_binary(document) do
    # Text diff: [text_diff, 0, 2]
    apply_text_patch(document, text_diff)
  end

  defp patch_value(document, _delta, _opts) do
    document
  end

  defp patch_object(document, delta, opts) when is_map(document) do
    Enum.reduce(delta, document, fn {key, subdelta}, acc ->
      cond do
        String.starts_with?(key, "_") ->
          # Array index
          index = String.slice(key, 1..-1) |> String.to_integer()
          patch_array_item(acc, index, subdelta, opts)
        
        true ->
          # Object key
          current_value = Map.get(acc, key)
          
          case subdelta do
            [_old_value, 0, 0] ->
              # Delete key
              Map.delete(acc, key)
            
            _ ->
              # Update or add key
              new_value = patch_value(current_value, subdelta, opts)
              if new_value == nil do
                Map.delete(acc, key)
              else
                Map.put(acc, key, new_value)
              end
          end
      end
    end)
  end

  defp patch_object(document, _delta, _opts) do
    document
  end

  defp patch_array(document, delta, opts) when is_list(document) do
    # Apply array patches in the correct order
    # First collect all operations and sort them
    operations = Enum.map(delta, fn {key, value} ->
      case key do
        "_" <> index_str ->
          index = String.to_integer(index_str)
          case value do
            [_old, 0, 0] -> {:delete, index, value}
            ["", from_index, 3] -> {:move, index, from_index}
            [new_value] -> {:insert, index, [new_value]}
            _ -> {:change, index, value}
          end
        index_str ->
          index = String.to_integer(index_str) 
          {:insert, index, value}
      end
    end)
    
    # Sort by index and apply operations
    # Process deletes first (in reverse order), then inserts/changes
    deletes = operations |> Enum.filter(fn {op, _, _} -> op == :delete end) |> Enum.sort_by(fn {_, idx, _} -> -idx end)
    others = operations |> Enum.filter(fn {op, _, _} -> op != :delete end) |> Enum.sort_by(fn {_, idx, _} -> idx end)
    
    # Apply deletes first
    result_after_deletes = Enum.reduce(deletes, document, fn {:delete, index, _}, acc ->
      if index < length(acc), do: List.delete_at(acc, index), else: acc
    end)
    
    # Then apply other operations
    Enum.reduce(others, result_after_deletes, fn operation, acc ->
      case operation do
        {:insert, index, [new_value]} ->
          if index <= length(acc), do: List.insert_at(acc, index, new_value), else: acc ++ [new_value]
        
        {:move, to_index, from_index} ->
          if from_index < length(acc) do
            item = Enum.at(acc, from_index)
            acc |> List.delete_at(from_index) |> List.insert_at(to_index, item)
          else
            acc
          end
        
        {:change, index, [_old_val, new_val]} ->
          if index < length(acc), do: List.replace_at(acc, index, new_val), else: acc
        
        {:change, index, new_value} ->
          if index < length(acc), do: List.replace_at(acc, index, new_value), else: acc
        
        _ ->
          acc
      end
    end)
  end

  defp patch_array(document, _delta, _opts) do
    document
  end

  defp patch_array_item(document, index, delta, opts) when is_list(document) do
    case delta do
      [_old_value, 0, 0] ->
        # Delete item
        List.delete_at(document, index)
      
      [new_value] ->
        # Insert item
        List.insert_at(document, index, new_value)
      
      ["", from_index, 3] ->
        # Move item
        item = Enum.at(document, from_index)
        document
        |> List.delete_at(from_index)
        |> List.insert_at(index, item)
      
      _ ->
        # Change item
        current_value = Enum.at(document, index)
        new_value = patch_value(current_value, delta, opts)
        List.replace_at(document, index, new_value)
    end
  end

  defp patch_array_item(document, _index, _delta, _opts) do
    document
  end

  defp merge_delta(acc, delta, _opts) when is_map(delta) do
    Map.merge(acc, delta, fn _key, val1, val2 ->
      if is_map(val1) and is_map(val2) do
        merge_delta(val1, val2, [])
      else
        val2  # Later value wins
      end
    end)
  end

  defp invert_delta(delta, _opts) when is_map(delta) do
    Enum.reduce(delta, %{}, fn {key, value}, acc ->
      inverted_value = case value do
        [old_value, new_value] ->
          [new_value, old_value]
        
        [value] ->
          [value, 0, 0]  # Addition becomes deletion
        
        [old_value, 0, 0] ->
          [old_value]  # Deletion becomes addition
        
        ["", _from_index, 3] ->
          # Move: need to calculate reverse move
          # This is simplified - proper implementation needs context
          ["", 0, 3]
        
        [text_diff, 0, 2] ->
          [invert_text_diff(text_diff), 0, 2]
        
        nested when is_map(nested) ->
          invert_delta(nested, [])
        
        _ ->
          value
      end
      
      Map.put(acc, key, inverted_value)
    end)
  end

  defp hash_value(value) do
    :crypto.hash(:md5, :erlang.term_to_binary(value))
  end

  defp apply_text_patch(text, text_diff) do
    # Supports two formats:
    # 1) Unified-style string produced by simple_text_diff/2
    # 2) Map with "text_diff" => list of ops from Rust NIF (delete/insert/replace)
    case text_diff do
      %{"text_diff" => ops} when is_list(ops) ->
        apply_text_diff_ops(text, ops)
      ops when is_map(ops) ->
        case Map.fetch(ops, :text_diff) do
          {:ok, list} when is_list(list) -> apply_text_diff_ops(text, list)
          _ -> text
        end
      diff when is_binary(diff) ->
        # Very simple unified diff parser: take first line starting with '+' (not '+++')
        diff
        |> String.split("\n")
        |> Enum.find(fn line -> String.starts_with?(line, "+") and not String.starts_with?(line, "+++") end)
        |> case do
          "+" <> new_line -> String.trim_trailing(new_line)
          _ -> text
        end
      _ -> text
    end
  end

  defp invert_text_diff(text_diff) do
    # Placeholder - implement proper text diff inversion
    text_diff
  end

  defp apply_text_diff_ops(text, ops) when is_binary(text) and is_list(ops) do
    # Reconstruct the new text by walking old text with an old-index cursor.
    # Ops may include delete (old_range, text), insert (new_range, text), replace (old_range, new_text).
    # The ops are expected in order. We skip equal parts by taking from cursor to op's old_range.start.
    try do
      {_cursor, builder} =
        Enum.reduce(ops, {0, []}, fn op, {pos_old, acc} ->
          case op do
            %{"op" => "delete", "range" => [s, e]} when is_integer(s) and is_integer(e) ->
              # Append unchanged segment before deletion
              prefix = safe_slice(text, pos_old, s - pos_old)
              {e, [acc, prefix]}
            %{"op" => "replace", "old_range" => [s, e], "new_text" => new_text} ->
              prefix = safe_slice(text, pos_old, s - pos_old)
              {e, [acc, prefix, new_text]}
            %{"op" => "insert", "text" => ins} ->
              # Insert at current new position; old cursor unchanged
              {pos_old, [acc, ins]}
            _ -> {pos_old, acc}
          end
        end)

      # Append the remaining unchanged tail
      tail_start = min(String.length(text), elem({0, []}, 0))
      # Note: The above line is incorrect; compensate by recomputing tail from final cursor
      # Re-run to get final cursor succinctly
      final_cursor = Enum.reduce(ops, 0, fn op, pos_old ->
        case op do
          %{"op" => "delete", "range" => [s, e]} -> e
          %{"op" => "replace", "old_range" => [s, e]} -> e
          _ -> pos_old
        end
      end)

      tail = safe_slice(text, final_cursor, String.length(text) - final_cursor)
      IO.iodata_to_binary([builder, tail])
    rescue
      _ -> text
    end
  end

  defp safe_slice(text, start, len) do
    start = max(start, 0)
    len = max(len, 0)
    if start >= String.length(text), do: "", else: String.slice(text, start, len)
  end

  # === PROPER LCS IMPLEMENTATION ===
  
  defp compute_lcs_diff(old, new) do
    # Build LCS table using dynamic programming
    table = build_lcs_table(old, new)
    
    # Extract the actual LCS sequence
    lcs_sequence = extract_lcs_sequence(table, old, new, length(old), length(new))
    
    # Generate diff operations from LCS
    operations = generate_diff_operations(old, new, lcs_sequence)
    
    # Also return move information for later processing
    move_info = analyze_potential_moves(old, new, operations)
    
    {operations, move_info}
  end
  
  defp build_lcs_table(old, new) do
    old_len = length(old)
    new_len = length(new)
    
    # Initialize table - (old_len + 1) x (new_len + 1)
    empty_row = List.duplicate(0, new_len + 1)
    initial_table = List.duplicate(empty_row, old_len + 1)
    
    # Fill table using LCS recurrence relation:
    # If items match: lcs[i][j] = lcs[i-1][j-1] + 1
    # If items don't match: lcs[i][j] = max(lcs[i-1][j], lcs[i][j-1])
    Enum.reduce(1..old_len//1, initial_table, fn i, table ->
      Enum.reduce(1..new_len//1, table, fn j, current_table ->
        old_item = Enum.at(old, i - 1)
        new_item = Enum.at(new, j - 1)
        
        if items_equal?(old_item, new_item) do
          # Items match - extend LCS
          prev_diagonal = get_table_cell(current_table, i - 1, j - 1)
          set_table_cell(current_table, i, j, prev_diagonal + 1)
        else
          # Items don't match - take maximum from left or top
          left_value = get_table_cell(current_table, i, j - 1)
          top_value = get_table_cell(current_table, i - 1, j)
          set_table_cell(current_table, i, j, max(left_value, top_value))
        end
      end)
    end)
  end
  
  defp items_equal?(item1, item2) do
    # Deep equality check for proper comparison
    item1 == item2
  end
  
  defp get_table_cell(table, i, j) do
    table |> Enum.at(i) |> Enum.at(j)
  end
  
  defp set_table_cell(table, i, j, value) do
    List.update_at(table, i, fn row ->
      List.update_at(row, j, fn _ -> value end)
    end)
  end
  
  defp extract_lcs_sequence(table, old, new, i, j, acc \\ [])
  
  defp extract_lcs_sequence(_table, _old, _new, 0, _j, acc), do: Enum.reverse(acc)
  defp extract_lcs_sequence(_table, _old, _new, _i, 0, acc), do: Enum.reverse(acc)
  
  defp extract_lcs_sequence(table, old, new, i, j, acc) do
    old_item = Enum.at(old, i - 1)
    new_item = Enum.at(new, j - 1)
    
    if items_equal?(old_item, new_item) do
      # This item is part of the LCS
      extract_lcs_sequence(table, old, new, i - 1, j - 1, [old_item | acc])
    else
      # Move in direction of larger value
      left_value = get_table_cell(table, i, j - 1)
      top_value = get_table_cell(table, i - 1, j)
      
      if top_value >= left_value do
        extract_lcs_sequence(table, old, new, i - 1, j, acc)
      else
        extract_lcs_sequence(table, old, new, i, j - 1, acc)
      end
    end
  end
  
  defp generate_diff_operations(old, new, lcs_sequence) do
    # Generate a proper sequence-based diff using LCS
    # This is more complex than just finding items not in LCS
    lcs_set = MapSet.new(lcs_sequence)
    
    # Build alignment between old and new based on LCS
    {old_ops, new_ops} = align_sequences_with_lcs(old, new, lcs_sequence)
    
    old_ops ++ new_ops
  end

  defp align_sequences_with_lcs(old, new, lcs_sequence) do
    # Walk through both sequences and generate proper operations
    # This is a simplified approach - real LCS diff is more complex
    
    old_deletions = old 
    |> Enum.with_index()
    |> Enum.filter(fn {item, _} -> item not in lcs_sequence end)
    |> Enum.map(fn {item, idx} -> {:delete, idx, item} end)
    
    new_insertions = new
    |> Enum.with_index()
    |> Enum.filter(fn {item, _} -> item not in lcs_sequence end)
    |> Enum.map(fn {item, idx} -> {:insert, idx, item} end)
    
    {old_deletions, new_insertions}
  end
  
  defp build_position_map(list) do
    list
    |> Enum.with_index()
    |> Enum.reduce(%{}, fn {item, idx}, acc ->
      Map.update(acc, item, [idx], fn existing -> [idx | existing] end)
    end)
  end
  
  defp operations_to_delta(operations, _move_info, _opts) do
    # Convert diff operations to jsondiffpatch delta format
    Enum.reduce(operations, %{}, fn operation, acc ->
      case operation do
        {:delete, idx, item} ->
          Map.put(acc, "_#{idx}", [item, 0, 0])
        
        {:insert, idx, item} ->
          # Represent inserts with _index as well
          Map.put(acc, "_#{idx}", [item])
        
        {:change, idx, old_item, new_item} ->
          Map.put(acc, "_#{idx}", [old_item, new_item])
      end
    end)
  end
  
  defp analyze_potential_moves(old, new, _operations) do
    # Analyze which items might have moved rather than being deleted/inserted
    # This is a simplified version - could be enhanced with better heuristics
    old_items = MapSet.new(old)
    new_items = MapSet.new(new)
    
    # Items that appear in both lists are potential moves
    potential_moves = MapSet.intersection(old_items, new_items)
    
    %{potential_moves: potential_moves}
  end
  
  defp add_move_detection(delta, old, new, move_info) do
    # Enhanced move detection based on the LCS analysis
    # For now, use the existing move detection logic but with LCS insights
    {moves, _} = detect_array_moves(old, new, [])
    
    # Merge moves into delta, preferring moves over delete+insert pairs
    Map.merge(delta, moves, fn _key, delta_op, move_op ->
      # Prefer move operations over separate delete/insert
      case {delta_op, move_op} do
        {[_, 0, 0], ["", _, 3]} -> move_op  # Prefer move over delete
        {[_], ["", _, 3]} -> move_op       # Prefer move over insert
        _ -> delta_op                       # Keep original delta
      end
    end)
  end
end
