defmodule JsonldEx.Diff.Operational do
  @moduledoc """
  CRDT-based operational diff for concurrent editing of JSON-LD documents.
  
  This implementation uses operation-based conflict-free replicated data types
  to generate diffs as sequences of operations that can be applied concurrently
  and merged without conflicts.
  
  Operations are based on the JSON CRDT paper by Bartosz Sypytkowski:
  https://www.bartoszsypytkowski.com/operation-based-crdts-json-document/
  """

  @type operation :: %{
    type: :set | :delete | :insert | :move | :copy,
    path: [atom() | integer()],
    value: term(),
    timestamp: integer(),
    actor_id: binary()
  }

  @type operational_diff :: %{
    operations: [operation()],
    metadata: %{
      actors: [binary()],
      timestamp_range: {integer(), integer()},
      conflict_resolution: :last_write_wins | :merge
    }
  }

  @doc """
  Generate operational diff between two JSON-LD documents.
  
  Returns a sequence of operations that transform old into new.
  Operations include timestamps and actor IDs for conflict resolution.
  """
  @spec diff(map(), map(), keyword()) :: {:ok, operational_diff()} | {:error, term()}
  def diff(old, new, opts \\ []) do
    actor_id = Keyword.get(opts, :actor_id, generate_actor_id())
    base_timestamp = Keyword.get(opts, :timestamp, System.system_time(:nanosecond))
    
    try do
      operations = diff_recursive(old, new, [], actor_id, base_timestamp)
      
      diff_result = %{
        operations: operations,
        metadata: %{
          actors: [actor_id],
          timestamp_range: calculate_timestamp_range(operations),
          conflict_resolution: Keyword.get(opts, :conflict_resolution, :last_write_wins)
        }
      }
      
      {:ok, diff_result}
    rescue
      error -> {:error, {:diff_failed, error}}
    end
  end

  @doc """
  Apply operational diff to a document.
  """
  @spec patch(map(), operational_diff(), keyword()) :: {:ok, map()} | {:error, term()}
  def patch(document, %{operations: operations}, opts \\ []) do
    try do
      result = Enum.reduce(operations, document, fn op, acc ->
        apply_operation(acc, op, opts)
      end)
      
      {:ok, result}
    rescue
      error -> {:error, {:patch_failed, error}}
    end
  end

  @doc """
  Validate that a patch can be applied to a document.
  """
  @spec validate_patch(map(), operational_diff(), keyword()) :: {:ok, boolean()} | {:error, term()}
  def validate_patch(document, %{operations: operations}, _opts \\ []) do
    try do
      valid = Enum.all?(operations, fn op ->
        validate_operation(document, op)
      end)
      
      {:ok, valid}
    rescue
      error -> {:error, {:validation_failed, error}}
    end
  end

  @doc """
  Merge multiple operational diffs.
  
  Operations are merged by timestamp, with conflict resolution
  based on the strategy specified.
  """
  @spec merge_diffs([operational_diff()], keyword()) :: {:ok, operational_diff()} | {:error, term()}
  def merge_diffs(diffs, opts \\ []) when is_list(diffs) do
    try do
      all_operations = 
        diffs
        |> Enum.flat_map(& &1.operations)
        |> Enum.sort_by(& &1.timestamp)
      
      all_actors = 
        diffs
        |> Enum.flat_map(&(&1.metadata.actors))
        |> Enum.uniq()
      
      conflict_resolution = 
        opts 
        |> Keyword.get(:conflict_resolution) 
        |> resolve_conflict_strategy(diffs)
      
      merged_operations = resolve_conflicts(all_operations, conflict_resolution)
      
      result = %{
        operations: merged_operations,
        metadata: %{
          actors: all_actors,
          timestamp_range: calculate_timestamp_range(merged_operations),
          conflict_resolution: conflict_resolution
        }
      }
      
      {:ok, result}
    rescue
      error -> {:error, {:merge_failed, error}}
    end
  end

  @doc """
  Generate the inverse of an operational diff.
  """
  @spec inverse(operational_diff(), keyword()) :: {:ok, operational_diff()} | {:error, term()}
  def inverse(%{operations: operations, metadata: metadata}, opts \\ []) do
    try do
      inverse_operations = 
        operations
        |> Enum.reverse()
        |> Enum.map(&invert_operation/1)
      
      result = %{
        operations: inverse_operations,
        metadata: Map.put(metadata, :conflict_resolution, :inverse)
      }
      
      {:ok, result}
    rescue
      error -> {:error, {:inverse_failed, error}}
    end
  end

  # Private functions

  defp diff_recursive(old, new, _path, _actor_id, _timestamp) when old == new do
    []
  end

  defp diff_recursive(old, new, path, actor_id, timestamp) when is_map(old) and is_map(new) do
    all_keys = MapSet.union(MapSet.new(Map.keys(old)), MapSet.new(Map.keys(new)))
    
    Enum.flat_map(all_keys, fn key ->
      old_val = Map.get(old, key)
      new_val = Map.get(new, key)
      new_path = path ++ [key]
      
      cond do
        old_val == nil ->
          [create_set_operation(new_path, new_val, actor_id, timestamp)]
        
        new_val == nil ->
          [create_delete_operation(new_path, actor_id, timestamp)]
        
        old_val != new_val ->
          if is_map(old_val) and is_map(new_val) do
            diff_recursive(old_val, new_val, new_path, actor_id, timestamp + 1)
          else
            [create_set_operation(new_path, new_val, actor_id, timestamp)]
          end
        
        true ->
          []
      end
    end)
  end

  defp diff_recursive(old, new, path, actor_id, timestamp) when is_list(old) and is_list(new) do
    diff_arrays(old, new, path, actor_id, timestamp)
  end

  defp diff_recursive(_old, new, path, actor_id, timestamp) do
    [create_set_operation(path, new, actor_id, timestamp)]
  end

  defp diff_arrays(old, new, path, actor_id, timestamp) do
    {deletes, changes, inserts} = lcs_diff_arrays(old, new)

    # Detect moves by pairing deletes and inserts of equal values
    {moves, deletes, inserts} = detect_moves(old, deletes, inserts)

    # Emit moves first (from original array)
    {ops_after_moves, ts_after_moves} =
      moves
      |> Enum.sort_by(fn {from, to} -> {from, to} end)
      |> Enum.map_reduce({[], timestamp}, fn {from, to}, {acc, ts} ->
        op = create_move_operation(path ++ [to], from, actor_id, ts)
        {[op | acc], ts + 1}
      end)
      |> then(fn {rev_ops, {[], ts}} -> {Enum.reverse(rev_ops), ts} end)

    # Emit deletes (from highest index to lowest)
    {ops_after_deletes, ts_after_deletes} =
      deletes
      |> Enum.sort_by(& &1, :desc)
      |> Enum.map_reduce({ops_after_moves, ts_after_moves}, fn idx, {acc, ts} ->
        op = create_delete_operation(path ++ [idx], actor_id, ts)
        {[op | acc], ts + 1}
      end)
      |> then(fn {rev_ops, {acc_ops, ts}} -> {acc_ops ++ Enum.reverse(rev_ops), ts} end)

    # Emit changes (replace at index)
    {ops_after_changes, ts_after_changes} =
      changes
      |> Enum.sort_by(fn {idx, _} -> idx end)
      |> Enum.map_reduce({ops_after_deletes, ts_after_deletes}, fn {idx, new_val}, {acc, ts} ->
        op = create_set_operation(path ++ [idx], new_val, actor_id, ts)
        {[op | acc], ts + 1}
      end)
      |> then(fn {rev_ops, {acc_ops, ts}} -> {acc_ops ++ Enum.reverse(rev_ops), ts} end)

    # Emit inserts (ascending index)
    {ops_final, ts_final} =
      inserts
      |> Enum.sort_by(fn {idx, _} -> idx end)
      |> Enum.map_reduce({ops_after_changes, ts_after_changes}, fn {idx, val}, {acc, ts} ->
        op = create_insert_operation(path ++ [idx], val, actor_id, ts)
        {[op | acc], ts + 1}
      end)
      |> then(fn {rev_ops, {acc_ops, ts}} -> {acc_ops ++ Enum.reverse(rev_ops), ts} end)

    ops_final
  end

  defp detect_moves(old, deletes, inserts) do
    # Map values to available old indices (from deletes only)
    del_map =
      deletes
      |> Enum.reduce(%{}, fn idx, acc ->
        val = Enum.at(old, idx)
        Map.update(acc, val, [idx], fn lst -> [idx | lst] end)
      end)

    # Pair inserts with deletes of the same value to form moves
    {moves, remaining_del_map, remaining_inserts} =
      inserts
      |> Enum.sort_by(fn {idx, _} -> idx end)
      |> Enum.reduce({[], del_map, []}, fn {j, v}, {mv, dm, ins_acc} ->
        case Map.get(dm, v, []) do
          [i | rest] when i != j ->
            # Use this delete as a move source
            new_dm = if rest == [], do: Map.delete(dm, v), else: Map.put(dm, v, rest)
            {[{i, j} | mv], new_dm, ins_acc}
          _ ->
            # No matching delete, keep as real insert
            {mv, dm, [{j, v} | ins_acc]}
        end
      end)

    remaining_inserts = Enum.reverse(remaining_inserts)

    # Rebuild remaining deletes list from remaining_del_map
    remaining_deletes = remaining_del_map |> Enum.flat_map(fn {_v, idxs} -> idxs end)

    {moves, Enum.uniq(remaining_deletes), remaining_inserts}
  end

  # Compute array edits using LCS to minimize deletes/inserts and detect in-place changes
  defp lcs_diff_arrays(old, new) do
    old_len = length(old)
    new_len = length(new)

    # DP table: (old_len+1) x (new_len+1)
    table = for _i <- 0..old_len, do: :array.new(new_len + 1, default: 0)

    # Fill table
    table =
      Enum.reduce(1..old_len, table, fn i, t ->
        Enum.reduce(1..new_len, t, fn j, tt ->
          a = Enum.at(old, i - 1)
          b = Enum.at(new, j - 1)
          val = if a == b do
            :array.get(j - 1, Enum.at(tt, i - 1)) + 1
          else
            max(:array.get(j, Enum.at(tt, i - 1)), :array.get(j - 1, Enum.at(tt, i)))
          end
          row = :array.set(j, val, Enum.at(tt, i))
          List.replace_at(tt, i, row)
        end)
      end)

    # Backtrack to get indices in LCS
    {i, j} = {old_len, new_len}
    lcs_positions = backtrack_lcs(table, old, new, i, j, [])

    lcs_old_idx = MapSet.new(Enum.map(lcs_positions, fn {oi, _nj} -> oi end))
    lcs_new_idx = MapSet.new(Enum.map(lcs_positions, fn {_oi, nj} -> nj end))

    # Deletes: old indices not in LCS
    deletes =
      Enum.with_index(old)
      |> Enum.reject(fn {_v, idx} -> MapSet.member?(lcs_old_idx, idx) end)
      |> Enum.map(fn {_v, idx} -> idx end)

    # Inserts: new indices not in LCS
    inserts =
      Enum.with_index(new)
      |> Enum.reject(fn {_v, idx} -> MapSet.member?(lcs_new_idx, idx) end)
      |> Enum.map(fn {v, idx} -> {idx, v} end)

    # Changes: positions where both arrays have an element at same index but differ
    common_len = min(old_len, new_len)
    changes =
      Enum.reduce(0..(common_len - 1), [], fn idx, acc ->
        a = Enum.at(old, idx)
        b = Enum.at(new, idx)
        if a != b and MapSet.member?(lcs_old_idx, idx) and MapSet.member?(lcs_new_idx, idx) do
          [{idx, b} | acc]
        else
          acc
        end
      end)
      |> Enum.reverse()

    {deletes, changes, inserts}
  end

  defp backtrack_lcs(_table, _old, _new, 0, 0, acc), do: Enum.reverse(acc)
  defp backtrack_lcs(table, old, new, i, 0, acc) when i > 0, do: backtrack_lcs(table, old, new, i - 1, 0, acc)
  defp backtrack_lcs(table, old, new, 0, j, acc) when j > 0, do: backtrack_lcs(table, old, new, 0, j - 1, acc)
  defp backtrack_lcs(table, old, new, i, j, acc) do
    a = Enum.at(old, i - 1)
    b = Enum.at(new, j - 1)
    cond do
      a == b -> backtrack_lcs(table, old, new, i - 1, j - 1, [{i - 1, j - 1} | acc])
      true ->
        up = :array.get(j, Enum.at(table, i - 1))
        left = :array.get(j - 1, Enum.at(table, i))
        if up >= left do
          backtrack_lcs(table, old, new, i - 1, j, acc)
        else
          backtrack_lcs(table, old, new, i, j - 1, acc)
        end
    end
  end

  defp create_move_operation(path, from_index, actor_id, timestamp) do
    %{
      type: :move,
      path: path,
      from: from_index,
      value: nil,
      timestamp: timestamp,
      actor_id: actor_id
    }
  end

  defp create_set_operation(path, value, actor_id, timestamp) do
    %{
      type: :set,
      path: path,
      value: value,
      timestamp: timestamp,
      actor_id: actor_id
    }
  end

  defp create_delete_operation(path, actor_id, timestamp) do
    %{
      type: :delete,
      path: path,
      value: nil,
      timestamp: timestamp,
      actor_id: actor_id
    }
  end

  defp create_insert_operation(path, value, actor_id, timestamp) do
    %{
      type: :insert,
      path: path,
      value: value,
      timestamp: timestamp,
      actor_id: actor_id
    }
  end

  defp apply_operation(document, %{type: :set, path: path, value: value}, _opts) do
    put_in(document, path, value)
  end

  defp apply_operation(document, %{type: :delete, path: path}, _opts) do
    {_deleted, result} = pop_in(document, path)
    result || document
  end

  defp apply_operation(document, %{type: :insert, path: path, value: value}, _opts) do
    case path do
      [] -> value
      [key] when is_map(document) -> Map.put(document, key, value)
      path -> put_in(document, path, value)
    end
  end

  defp apply_operation(document, %{type: :move, path: path, from: from_index}, _opts) do
    # path includes the destination index as last element
    case {Enum.split(path, length(path) - 1), document} do
      {{container_path, [to_index]}, doc} when is_integer(to_index) ->
        case get_in(doc, container_path) do
          arr when is_list(arr) ->
            if from_index >= 0 and from_index < length(arr) do
              item = Enum.at(arr, from_index)
              arr_removed = List.delete_at(arr, from_index)
              # Adjust destination index if removing from before the insertion point
              adjusted_to =
                if from_index < to_index do
                  max(to_index - 1, 0)
                else
                  to_index
                end
              insert_at = min(max(adjusted_to, 0), length(arr_removed))
              new_arr = List.insert_at(arr_removed, insert_at, item)
              put_in(doc, container_path, new_arr)
            else
              doc
            end
          _ -> doc
        end
      _ -> document
    end
  end

  defp validate_operation(document, %{type: :set, path: path}) do
    path_exists?(document, Enum.drop(path, -1))
  end

  defp validate_operation(document, %{type: :delete, path: path}) do
    path_exists?(document, path)
  end

  defp validate_operation(document, %{type: :insert, path: path}) do
    case path do
      [] -> true
      [_] -> is_map(document)
      _ -> path_exists?(document, Enum.drop(path, -1))
    end
  end

  defp validate_operation(document, %{type: :move, path: path, from: from_index}) do
    case Enum.split(path, length(path) - 1) do
      {container_path, [to_index]} when is_integer(to_index) and is_integer(from_index) ->
        case get_in(document, container_path) do
          arr when is_list(arr) ->
            from_index >= 0 and from_index < length(arr) and to_index >= 0 and to_index <= length(arr)
          _ -> false
        end
      _ -> false
    end
  end

  defp path_exists?(_document, []) do
    true
  end

  defp path_exists?(document, [key | rest]) when is_map(document) do
    case Map.get(document, key) do
      nil -> false
      value -> path_exists?(value, rest)
    end
  end

  defp path_exists?(document, [index | rest]) when is_list(document) and is_integer(index) do
    if index >= 0 and index < length(document) do
      value = Enum.at(document, index)
      path_exists?(value, rest)
    else
      false
    end
  end

  defp path_exists?(_document, _path) do
    false
  end

  defp resolve_conflicts(operations, :last_write_wins) do
    operations
    |> Enum.group_by(& &1.path)
    |> Enum.map(fn {_path, ops} ->
      Enum.max_by(ops, & &1.timestamp)
    end)
    |> Enum.sort_by(& &1.timestamp)
  end

  defp resolve_conflicts(operations, :merge) do
    operations
  end

  defp invert_operation(%{type: :set, path: path, value: _value} = op) do
    %{op | type: :delete, value: nil}
  end

  defp invert_operation(%{type: :delete, path: path, value: nil} = op) do
    %{op | type: :set, value: nil}
  end

  defp invert_operation(%{type: :insert} = op) do
    %{op | type: :delete, value: nil}
  end

  defp generate_actor_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end

  defp calculate_timestamp_range([]) do
    {0, 0}
  end

  defp calculate_timestamp_range(operations) do
    timestamps = Enum.map(operations, & &1.timestamp)
    {Enum.min(timestamps), Enum.max(timestamps)}
  end

  defp resolve_conflict_strategy(nil, diffs) do
    diffs
    |> Enum.map(& &1.metadata.conflict_resolution)
    |> Enum.at(0, :last_write_wins)
  end

  defp resolve_conflict_strategy(strategy, _diffs) do
    strategy
  end
end
