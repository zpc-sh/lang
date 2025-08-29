defmodule Lang.Agent.CoordinatorTest do
  use ExUnit.Case, async: true

  alias Lang.Agent.Coordinator

  test "fanout coordinates across agents and merges results" do
    agent_ids = ["codex", "claude"]

    task = %{
      strategy: :fanout,
      delegate_fun: fn id, _task -> {:ok, %{agent: id, score: 1}} end
    }

    assert {:ok, %{results: results, merged: merged}} =
             Coordinator.coordinate(agent_ids, task, :fanout)

    # Results contain tuples of {id, {:ok, payload}}
    assert Enum.all?(results, fn {id, {:ok, %{agent: agent}}} -> id == agent end)
    assert merged[:total] == length(agent_ids)
    assert merged[:success] == length(agent_ids)
    assert merged[:errors] == 0
  end

  test "first_success stops at first ok and returns winner" do
    agent_ids = ["codex", "claude", "buddy"]

    task = %{
      strategy: :first_success,
      delegate_fun: fn id, _task ->
        if id == "codex", do: {:error, :nope}, else: {:ok, %{agent: id}}
      end
    }

    assert {:ok, %{results: results, merged: merged, winner: winner}} =
             Coordinator.coordinate(agent_ids, task, :first_success)

    assert winner in ["claude", "buddy"]
    assert is_list(results)
    assert merged[:total] == length(results)
  end

  test "map_reduce collects payloads and applies reducer" do
    agent_ids = ["a1", "a2", "a3"]

    task = %{
      strategy: :map_reduce,
      reduce_fun: fn payloads -> Enum.count(payloads) end,
      delegate_fun: fn id, _task -> {:ok, %{agent: id, val: 1}} end
    }

    assert {:ok, %{merged: merged}} = Coordinator.coordinate(agent_ids, task, :map_reduce)
    assert merged[:totals][:total] == 3
    assert is_list(merged[:merged_payloads])
    assert merged[:reduced] == 3
  end
end
