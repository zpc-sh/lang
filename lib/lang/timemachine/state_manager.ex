defmodule Lang.TimeMachine.StateManager do
  @moduledoc """
  Manages temporal states and transitions for content evolution
  """

  use GenServer
  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Logger.info("Starting Time Machine State Manager")

    {:ok,
     %{
       timelines: %{},
       states: %{},
       snapshots: %{},
       stats: %{total_timelines: 0, total_states: 0}
     }}
  end

  def create_timeline(content_id, initial_state, metadata \\ %{}) do
    GenServer.call(__MODULE__, {:create_timeline, content_id, initial_state, metadata})
  end

  def store_timeline(timeline) do
    GenServer.call(__MODULE__, {:store_timeline, timeline})
  end

  def get_timeline(timeline_id) do
    GenServer.call(__MODULE__, {:get_timeline, timeline_id})
  end

  def add_state(timeline_id, state_data, metadata \\ %{}) do
    GenServer.call(__MODULE__, {:add_state, timeline_id, state_data, metadata})
  end

  def get_state(timeline_id, state_id) do
    GenServer.call(__MODULE__, {:get_state, timeline_id, state_id})
  end

  def navigate_to_state(timeline_id, state_id) do
    GenServer.call(__MODULE__, {:navigate_to_state, timeline_id, state_id})
  end

  def create_branch(timeline_id, from_state_id, branch_name) do
    GenServer.call(__MODULE__, {:create_branch, timeline_id, from_state_id, branch_name})
  end

  def merge_branch(timeline_id, branch_name, target_state_id) do
    GenServer.call(__MODULE__, {:merge_branch, timeline_id, branch_name, target_state_id})
  end

  def create_snapshot(timeline_id, snapshot_name, description \\ "") do
    GenServer.call(__MODULE__, {:create_snapshot, timeline_id, snapshot_name, description})
  end

  def restore_snapshot(snapshot_id) do
    GenServer.call(__MODULE__, {:restore_snapshot, snapshot_id})
  end

  def get_timeline_history(timeline_id, options \\ %{}) do
    GenServer.call(__MODULE__, {:get_history, timeline_id, options})
  end

  def search_timelines(query, filters \\ %{}) do
    GenServer.call(__MODULE__, {:search_timelines, query, filters})
  end

  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  @impl true
  def handle_call({:create_timeline, content_id, initial_state, metadata}, _from, state) do
    timeline_id = generate_timeline_id()
    initial_state_id = generate_state_id()

    initial_state_entry = %{
      id: initial_state_id,
      timeline_id: timeline_id,
      state_data: initial_state,
      metadata: metadata,
      position: 0,
      created_at: DateTime.utc_now(),
      parent_id: nil,
      branch_name: "main"
    }

    timeline = %{
      id: timeline_id,
      content_id: content_id,
      created_at: DateTime.utc_now(),
      current_state: initial_state_id,
      current_position: 0,
      states: %{initial_state_id => initial_state_entry},
      branches: %{
        "main" => %{
          name: "main",
          created_at: DateTime.utc_now(),
          head_state: initial_state_id,
          states: [initial_state_id]
        }
      },
      metadata: metadata
    }

    timelines = Map.put(state.timelines, timeline_id, timeline)
    states = Map.put(state.states, initial_state_id, initial_state_entry)

    updated_stats = %{
      state.stats
      | total_timelines: state.stats.total_timelines + 1,
        total_states: state.stats.total_states + 1
    }

    Logger.info("Created new timeline", timeline_id: timeline_id, content_id: content_id)

    {:reply, {:ok, timeline},
     %{state | timelines: timelines, states: states, stats: updated_stats}}
  end

  @impl true
  def handle_call({:store_timeline, timeline}, _from, state) do
    timelines = Map.put(state.timelines, timeline.id, timeline)
    {:reply, {:ok, timeline}, %{state | timelines: timelines}}
  end

  @impl true
  def handle_call({:get_timeline, timeline_id}, _from, state) do
    case Map.get(state.timelines, timeline_id) do
      nil -> {:reply, {:error, :timeline_not_found}, state}
      timeline -> {:reply, {:ok, timeline}, state}
    end
  end

  @impl true
  def handle_call({:add_state, timeline_id, state_data, metadata}, _from, state) do
    case Map.get(state.timelines, timeline_id) do
      nil ->
        {:reply, {:error, :timeline_not_found}, state}

      timeline ->
        state_id = generate_state_id()
        position = timeline.current_position + 1

        new_state_entry = %{
          id: state_id,
          timeline_id: timeline_id,
          state_data: state_data,
          metadata: metadata,
          position: position,
          created_at: DateTime.utc_now(),
          parent_id: timeline.current_state,
          branch_name: get_current_branch(timeline)
        }

        # Update timeline
        updated_timeline = %{
          timeline
          | current_state: state_id,
            current_position: position,
            states: Map.put(timeline.states, state_id, new_state_entry)
        }

        # Update branch
        current_branch_name = get_current_branch(timeline)
        current_branch = timeline.branches[current_branch_name]

        updated_branch = %{
          current_branch
          | head_state: state_id,
            states: current_branch.states ++ [state_id]
        }

        final_timeline = %{
          updated_timeline
          | branches: Map.put(timeline.branches, current_branch_name, updated_branch)
        }

        # Update state
        timelines = Map.put(state.timelines, timeline_id, final_timeline)
        states = Map.put(state.states, state_id, new_state_entry)
        updated_stats = %{state.stats | total_states: state.stats.total_states + 1}

        Logger.info("Added state to timeline",
          timeline_id: timeline_id,
          state_id: state_id,
          position: position
        )

        {:reply, {:ok, new_state_entry},
         %{state | timelines: timelines, states: states, stats: updated_stats}}
    end
  end

  @impl true
  def handle_call({:get_state, timeline_id, state_id}, _from, state) do
    case {Map.get(state.timelines, timeline_id), Map.get(state.states, state_id)} do
      {nil, _} ->
        {:reply, {:error, :timeline_not_found}, state}

      {_, nil} ->
        {:reply, {:error, :state_not_found}, state}

      {timeline, state_entry} ->
        if state_entry.timeline_id == timeline_id do
          {:reply, {:ok, state_entry}, state}
        else
          {:reply, {:error, :state_not_in_timeline}, state}
        end
    end
  end

  @impl true
  def handle_call({:navigate_to_state, timeline_id, state_id}, _from, state) do
    case Map.get(state.timelines, timeline_id) do
      nil ->
        {:reply, {:error, :timeline_not_found}, state}

      timeline ->
        case Map.get(timeline.states, state_id) do
          nil ->
            {:reply, {:error, :state_not_found}, state}

          target_state ->
            updated_timeline = %{
              timeline
              | current_state: state_id,
                current_position: target_state.position
            }

            timelines = Map.put(state.timelines, timeline_id, updated_timeline)

            Logger.info("Navigated to state",
              timeline_id: timeline_id,
              state_id: state_id,
              position: target_state.position
            )

            {:reply, {:ok, target_state}, %{state | timelines: timelines}}
        end
    end
  end

  @impl true
  def handle_call({:create_branch, timeline_id, from_state_id, branch_name}, _from, state) do
    case Map.get(state.timelines, timeline_id) do
      nil ->
        {:reply, {:error, :timeline_not_found}, state}

      timeline ->
        case Map.get(timeline.states, from_state_id) do
          nil ->
            {:reply, {:error, :state_not_found}, state}

          from_state ->
            if Map.has_key?(timeline.branches, branch_name) do
              {:reply, {:error, :branch_already_exists}, state}
            else
              new_branch = %{
                name: branch_name,
                created_at: DateTime.utc_now(),
                parent_state: from_state_id,
                head_state: from_state_id,
                states: [from_state_id]
              }

              updated_timeline = %{
                timeline
                | branches: Map.put(timeline.branches, branch_name, new_branch)
              }

              timelines = Map.put(state.timelines, timeline_id, updated_timeline)

              Logger.info("Created branch",
                timeline_id: timeline_id,
                branch_name: branch_name,
                from_state: from_state_id
              )

              {:reply, {:ok, new_branch}, %{state | timelines: timelines}}
            end
        end
    end
  end

  @impl true
  def handle_call({:merge_branch, timeline_id, branch_name, target_state_id}, _from, state) do
    case Map.get(state.timelines, timeline_id) do
      nil ->
        {:reply, {:error, :timeline_not_found}, state}

      timeline ->
        case {Map.get(timeline.branches, branch_name), Map.get(timeline.states, target_state_id)} do
          {nil, _} ->
            {:reply, {:error, :branch_not_found}, state}

          {_, nil} ->
            {:reply, {:error, :target_state_not_found}, state}

          {branch, _target_state} ->
            merge_state_id = generate_state_id()
            position = timeline.current_position + 1

            merge_state_data = create_merge_state(timeline, branch, target_state_id)

            merge_state_entry = %{
              id: merge_state_id,
              timeline_id: timeline_id,
              state_data: merge_state_data,
              metadata: %{
                type: :merge,
                merged_branch: branch_name,
                target_state: target_state_id
              },
              position: position,
              created_at: DateTime.utc_now(),
              parent_id: target_state_id,
              branch_name: "main"
            }

            updated_timeline = %{
              timeline
              | current_state: merge_state_id,
                current_position: position,
                states: Map.put(timeline.states, merge_state_id, merge_state_entry)
            }

            # Update main branch
            main_branch = updated_timeline.branches["main"]

            updated_main_branch = %{
              main_branch
              | head_state: merge_state_id,
                states: main_branch.states ++ [merge_state_id]
            }

            final_timeline = %{
              updated_timeline
              | branches: Map.put(updated_timeline.branches, "main", updated_main_branch)
            }

            timelines = Map.put(state.timelines, timeline_id, final_timeline)
            states = Map.put(state.states, merge_state_id, merge_state_entry)
            updated_stats = %{state.stats | total_states: state.stats.total_states + 1}

            Logger.info("Merged branch",
              timeline_id: timeline_id,
              branch_name: branch_name,
              merge_state: merge_state_id
            )

            {:reply, {:ok, merge_state_entry},
             %{state | timelines: timelines, states: states, stats: updated_stats}}
        end
    end
  end

  @impl true
  def handle_call({:create_snapshot, timeline_id, snapshot_name, description}, _from, state) do
    case Map.get(state.timelines, timeline_id) do
      nil ->
        {:reply, {:error, :timeline_not_found}, state}

      timeline ->
        snapshot_id = generate_snapshot_id()

        snapshot = %{
          id: snapshot_id,
          timeline_id: timeline_id,
          name: snapshot_name,
          description: description,
          created_at: DateTime.utc_now(),
          timeline_state: timeline.current_state,
          full_timeline: timeline
        }

        snapshots = Map.put(state.snapshots, snapshot_id, snapshot)

        Logger.info("Created snapshot",
          timeline_id: timeline_id,
          snapshot_name: snapshot_name,
          snapshot_id: snapshot_id
        )

        {:reply, {:ok, snapshot}, %{state | snapshots: snapshots}}
    end
  end

  @impl true
  def handle_call({:restore_snapshot, snapshot_id}, _from, state) do
    case Map.get(state.snapshots, snapshot_id) do
      nil ->
        {:reply, {:error, :snapshot_not_found}, state}

      snapshot ->
        restored_timeline = snapshot.full_timeline
        timelines = Map.put(state.timelines, restored_timeline.id, restored_timeline)

        Logger.info("Restored snapshot",
          snapshot_id: snapshot_id,
          timeline_id: restored_timeline.id
        )

        {:reply, {:ok, restored_timeline}, %{state | timelines: timelines}}
    end
  end

  @impl true
  def handle_call({:get_history, timeline_id, options}, _from, state) do
    case Map.get(state.timelines, timeline_id) do
      nil ->
        {:reply, {:error, :timeline_not_found}, state}

      timeline ->
        history = build_timeline_history(timeline, options)
        {:reply, {:ok, history}, state}
    end
  end

  @impl true
  def handle_call({:search_timelines, query, filters}, _from, state) do
    results =
      state.timelines
      |> Map.values()
      |> filter_timelines(filters)
      |> search_timeline_content(query)
      |> Enum.map(&timeline_summary/1)

    {:reply, {:ok, results}, state}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    detailed_stats = %{
      total_timelines: state.stats.total_timelines,
      total_states: state.stats.total_states,
      total_snapshots: map_size(state.snapshots),
      active_timelines: count_active_timelines(state.timelines),
      avg_states_per_timeline: calculate_avg_states_per_timeline(state.timelines),
      branches_by_timeline: count_branches_by_timeline(state.timelines)
    }

    {:reply, detailed_stats, state}
  end

  # Private helper functions

  defp get_current_branch(timeline) do
    # For simplicity, assume current branch is the one containing current state
    Enum.find_value(timeline.branches, "main", fn {branch_name, branch} ->
      if timeline.current_state in branch.states, do: branch_name
    end)
  end

  defp create_merge_state(timeline, branch, target_state_id) do
    # This would implement actual merge logic
    # For now, return a simple merge indicator
    %{
      type: :merge,
      branch_name: branch.name,
      target_state: target_state_id,
      merged_at: DateTime.utc_now(),
      changes: "Merged #{branch.name} into main branch"
    }
  end

  defp build_timeline_history(timeline, options) do
    limit = Map.get(options, :limit, 50)
    include_branches = Map.get(options, :include_branches, true)

    states =
      timeline.states
      |> Map.values()
      |> Enum.sort_by(& &1.position)
      |> Enum.take(limit)

    history = %{
      timeline_id: timeline.id,
      content_id: timeline.content_id,
      total_states: map_size(timeline.states),
      states: states,
      current_state: timeline.current_state,
      current_position: timeline.current_position
    }

    if include_branches do
      Map.put(history, :branches, timeline.branches)
    else
      history
    end
  end

  defp filter_timelines(timelines, filters) do
    timelines
    |> filter_by_content_id(Map.get(filters, :content_id))
    |> filter_by_date_range(Map.get(filters, :date_from), Map.get(filters, :date_to))
    |> filter_by_branch_count(Map.get(filters, :min_branches))
  end

  defp filter_by_content_id(timelines, nil), do: timelines

  defp filter_by_content_id(timelines, content_id) do
    Enum.filter(timelines, fn timeline -> timeline.content_id == content_id end)
  end

  defp filter_by_date_range(timelines, nil, nil), do: timelines

  defp filter_by_date_range(timelines, date_from, date_to) do
    from_datetime = if date_from, do: DateTime.from_iso8601(date_from), else: nil
    to_datetime = if date_to, do: DateTime.from_iso8601(date_to), else: nil

    Enum.filter(timelines, fn timeline ->
      from_ok =
        case from_datetime do
          {:ok, from_dt, _} -> DateTime.compare(timeline.created_at, from_dt) != :lt
          _ -> true
        end

      to_ok =
        case to_datetime do
          {:ok, to_dt, _} -> DateTime.compare(timeline.created_at, to_dt) != :gt
          _ -> true
        end

      from_ok and to_ok
    end)
  end

  defp filter_by_branch_count(timelines, nil), do: timelines

  defp filter_by_branch_count(timelines, min_branches) do
    Enum.filter(timelines, fn timeline ->
      map_size(timeline.branches) >= min_branches
    end)
  end

  defp search_timeline_content(timelines, query) when is_nil(query) or query == "", do: timelines

  defp search_timeline_content(timelines, query) do
    query_lower = String.downcase(query)

    Enum.filter(timelines, fn timeline ->
      # Search in timeline metadata and state data
      content_matches =
        timeline.states
        |> Map.values()
        |> Enum.any?(fn state ->
          state_content = inspect(state.state_data) |> String.downcase()
          String.contains?(state_content, query_lower)
        end)

      metadata_matches =
        timeline.metadata
        |> inspect()
        |> String.downcase()
        |> String.contains?(query_lower)

      content_matches or metadata_matches
    end)
  end

  defp timeline_summary(timeline) do
    %{
      id: timeline.id,
      content_id: timeline.content_id,
      created_at: timeline.created_at,
      current_position: timeline.current_position,
      total_states: map_size(timeline.states),
      total_branches: map_size(timeline.branches),
      branch_names: Map.keys(timeline.branches)
    }
  end

  defp count_active_timelines(timelines) do
    # Consider a timeline active if it has states added in the last hour
    one_hour_ago = DateTime.add(DateTime.utc_now(), -3600, :second)

    timelines
    |> Map.values()
    |> Enum.count(fn timeline ->
      timeline.states
      |> Map.values()
      |> Enum.any?(fn state ->
        DateTime.compare(state.created_at, one_hour_ago) == :gt
      end)
    end)
  end

  defp calculate_avg_states_per_timeline(timelines) when map_size(timelines) == 0, do: 0

  defp calculate_avg_states_per_timeline(timelines) do
    total_states =
      timelines
      |> Map.values()
      |> Enum.map(fn timeline -> map_size(timeline.states) end)
      |> Enum.sum()

    total_states / map_size(timelines)
  end

  defp count_branches_by_timeline(timelines) do
    timelines
    |> Map.values()
    |> Enum.map(fn timeline ->
      {timeline.id, map_size(timeline.branches)}
    end)
    |> Enum.into(%{})
  end

  defp generate_timeline_id, do: :crypto.strong_rand_bytes(16) |> Base.encode64()
  defp generate_state_id, do: :crypto.strong_rand_bytes(12) |> Base.encode64()
  defp generate_snapshot_id, do: :crypto.strong_rand_bytes(12) |> Base.encode64()
end
