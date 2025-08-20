defmodule Lang.TimeMachine.Core do
  @moduledoc """
  Core module for time machine functionality - provides high-level API for temporal operations
  """

  alias Lang.TimeMachine.StateManager

  @doc """
  Create a new timeline for content evolution tracking
  """
  def create_timeline(content_id, initial_state, metadata \\ %{}) do
    StateManager.create_timeline(content_id, initial_state, metadata)
  end

  @doc """
  Add a new state to an existing timeline
  """
  def add_state(timeline_id, state_data, metadata \\ %{}) do
    StateManager.add_state(timeline_id, state_data, metadata)
  end

  @doc """
  Navigate to a specific state in the timeline
  """
  def navigate_to_state(timeline_id, state_id) do
    StateManager.navigate_to_state(timeline_id, state_id)
  end

  @doc """
  Create a branch from a specific state
  """
  def create_branch(timeline_id, from_state_id, branch_name) do
    StateManager.create_branch(timeline_id, from_state_id, branch_name)
  end

  @doc """
  Get the current state of a timeline
  """
  def get_current_state(timeline_id) do
    case StateManager.get_timeline(timeline_id) do
      {:ok, timeline} ->
        StateManager.get_state(timeline_id, timeline.current_state)

      error ->
        error
    end
  end

  @doc """
  Get the full history of a timeline
  """
  def get_timeline_history(timeline_id, options \\ %{}) do
    StateManager.get_timeline_history(timeline_id, options)
  end

  @doc """
  Create a snapshot of the current timeline state
  """
  def create_snapshot(timeline_id, snapshot_name, description \\ "") do
    StateManager.create_snapshot(timeline_id, snapshot_name, description)
  end

  @doc """
  Restore a timeline from a snapshot
  """
  def restore_snapshot(snapshot_id) do
    StateManager.restore_snapshot(snapshot_id)
  end

  @doc """
  Merge a branch back into the main timeline
  """
  def merge_branch(timeline_id, branch_name, target_state_id) do
    StateManager.merge_branch(timeline_id, branch_name, target_state_id)
  end

  @doc """
  Get statistics about time machine usage
  """
  def get_stats do
    StateManager.get_stats()
  end

  @doc """
  Search across all timelines
  """
  def search_timelines(query, filters \\ %{}) do
    StateManager.search_timelines(query, filters)
  end

  @doc """
  Calculate the diff between two states
  """
  def diff_states(timeline_id, from_state_id, to_state_id) do
    with {:ok, from_state} <- StateManager.get_state(timeline_id, from_state_id),
         {:ok, to_state} <- StateManager.get_state(timeline_id, to_state_id) do
      diff = %{
        timeline_id: timeline_id,
        from_state: from_state_id,
        to_state: to_state_id,
        from_position: from_state.position,
        to_position: to_state.position,
        time_diff: DateTime.diff(to_state.created_at, from_state.created_at, :second),
        changes: calculate_state_changes(from_state.state_data, to_state.state_data)
      }

      {:ok, diff}
    end
  end

  @doc """
  Replay timeline changes between two states
  """
  def replay_timeline(timeline_id, from_state_id, to_state_id, options \\ %{}) do
    with {:ok, timeline} <- StateManager.get_timeline(timeline_id),
         {:ok, from_state} <- StateManager.get_state(timeline_id, from_state_id),
         {:ok, to_state} <- StateManager.get_state(timeline_id, to_state_id) do
      # Get all states between from and to
      states_between = get_states_between(timeline, from_state.position, to_state.position)

      replay_data = %{
        timeline_id: timeline_id,
        start_state: from_state_id,
        end_state: to_state_id,
        total_steps: length(states_between),
        replay_speed: Map.get(options, :speed, 1.0),
        include_metadata: Map.get(options, :include_metadata, false),
        states: states_between
      }

      {:ok, replay_data}
    end
  end

  @doc """
  Get timeline analytics and insights
  """
  def analyze_timeline(timeline_id) do
    with {:ok, timeline} <- StateManager.get_timeline(timeline_id) do
      analysis = %{
        timeline_id: timeline_id,
        total_states: map_size(timeline.states),
        total_branches: map_size(timeline.branches),
        creation_date: timeline.created_at,
        activity_pattern: analyze_activity_pattern(timeline),
        branch_utilization: analyze_branch_utilization(timeline),
        state_complexity: analyze_state_complexity(timeline),
        evolution_velocity: calculate_evolution_velocity(timeline)
      }

      {:ok, analysis}
    end
  end

  # Private helper functions

  defp calculate_state_changes(from_data, to_data) do
    # Simple change calculation - in production this would be more sophisticated
    %{
      type: :basic_diff,
      from_size: byte_size(inspect(from_data)),
      to_size: byte_size(inspect(to_data)),
      estimated_changes: if(from_data == to_data, do: 0, else: 1)
    }
  end

  defp get_states_between(timeline, from_position, to_position) do
    timeline.states
    |> Map.values()
    |> Enum.filter(fn state ->
      state.position >= from_position and state.position <= to_position
    end)
    |> Enum.sort_by(& &1.position)
  end

  defp analyze_activity_pattern(timeline) do
    states = Map.values(timeline.states)

    if length(states) < 2 do
      %{pattern: :insufficient_data}
    else
      # Group states by hour of day
      hourly_activity =
        states
        |> Enum.group_by(fn state ->
          state.created_at.hour
        end)
        |> Enum.map(fn {hour, states_in_hour} ->
          {hour, length(states_in_hour)}
        end)
        |> Enum.into(%{})

      peak_hour =
        hourly_activity
        |> Enum.max_by(fn {_hour, count} -> count end)
        |> elem(0)

      %{
        pattern: :analyzed,
        peak_hour: peak_hour,
        hourly_distribution: hourly_activity,
        total_active_hours: map_size(hourly_activity)
      }
    end
  end

  defp analyze_branch_utilization(timeline) do
    if map_size(timeline.branches) <= 1 do
      %{utilization: :single_branch}
    else
      branch_stats =
        timeline.branches
        |> Enum.map(fn {name, branch} ->
          {name,
           %{
             state_count: length(branch.states),
             created_at: branch.created_at,
             is_active: branch.head_state == timeline.current_state
           }}
        end)
        |> Enum.into(%{})

      most_used_branch =
        branch_stats
        |> Enum.max_by(fn {_name, stats} -> stats.state_count end)
        |> elem(0)

      %{
        utilization: :multi_branch,
        branch_count: map_size(timeline.branches),
        most_used_branch: most_used_branch,
        branch_details: branch_stats
      }
    end
  end

  defp analyze_state_complexity(timeline) do
    states = Map.values(timeline.states)

    complexities =
      Enum.map(states, fn state ->
        # Simple complexity measure based on data size
        byte_size(inspect(state.state_data))
      end)

    if length(complexities) == 0 do
      %{complexity: :no_data}
    else
      avg_complexity = Enum.sum(complexities) / length(complexities)
      max_complexity = Enum.max(complexities)
      min_complexity = Enum.min(complexities)

      %{
        complexity: :analyzed,
        average_size: avg_complexity,
        max_size: max_complexity,
        min_size: min_complexity,
        complexity_trend: if(max_complexity > min_complexity * 2, do: :increasing, else: :stable)
      }
    end
  end

  defp calculate_evolution_velocity(timeline) do
    states =
      timeline.states
      |> Map.values()
      |> Enum.sort_by(& &1.position)

    if length(states) < 2 do
      %{velocity: :insufficient_data}
    else
      first_state = List.first(states)
      last_state = List.last(states)

      total_time = DateTime.diff(last_state.created_at, first_state.created_at, :second)
      total_changes = length(states) - 1

      if total_time == 0 do
        %{velocity: :instant}
      else
        changes_per_hour = total_changes * 3600 / total_time

        %{
          velocity: :calculated,
          changes_per_hour: changes_per_hour,
          total_duration_seconds: total_time,
          total_changes: total_changes,
          velocity_category: categorize_velocity(changes_per_hour)
        }
      end
    end
  end

  defp categorize_velocity(changes_per_hour) when changes_per_hour > 10, do: :high
  defp categorize_velocity(changes_per_hour) when changes_per_hour > 1, do: :medium
  defp categorize_velocity(_), do: :low
end
