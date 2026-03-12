defmodule Lang.Agent.PreferenceTest do
  use Lang.DataCase, async: false

  alias Lang.Agent.Agent
  alias Lang.Agent.Coordinator

  defp create_agent!(name, caps) do
    {:ok, agent} =
      Agent.spawn(%{
        capabilities: caps,
        constraints: %{},
        metadata: %{name: name}
      })

    agent
  end

  test "compute-heavy tasks prefer codex" do
    codex = create_agent!("codex", [:analysis, :single_file_edit])
    claude = create_agent!("claude", [:analysis, :multi_file_coordination])

    task = %{
      type: :generation,
      goal: "optimize code",
      delegate_fun: fn id, _t -> {:ok, %{id: id}} end
    }

    {:ok, %{results: results, merged: merged}} =
      Coordinator.coordinate([claude.id, codex.id], task, :fanout)

    # In fanout we can't assert ordering from results, but preference should affect first_success
    assert merged[:total] == 2

    {:ok, %{winner: winner}} = Coordinator.coordinate([claude.id, codex.id], task, :first_success)
    assert winner == codex.id
  end

  test "coordination-heavy tasks prefer claude" do
    codex = create_agent!("codex", [:analysis, :single_file_edit])
    claude = create_agent!("claude", [:analysis, :multi_file_coordination])

    task = %{
      type: :coordination,
      strategy: :map_reduce,
      reduce_fun: fn payloads -> length(payloads) end,
      delegate_fun: fn id, _t -> {:ok, %{id: id}} end
    }

    {:ok, %{winner: winner}} = Coordinator.coordinate([codex.id, claude.id], task, :first_success)
    assert winner == claude.id
  end
end
