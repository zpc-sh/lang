defmodule Lang.Agent.CoordinationSummary do
  @moduledoc """
  Ash resource to persist multi-agent coordination summaries.

  Falls back to in-memory usage via callers if DB isn't available. This resource
  is optional for environments without DB.
  """

  use Ash.Resource,
    domain: Lang.Agent,
    data_layer: AshPostgres.DataLayer

  postgres do
    table("agent_coordination_summaries")
    repo(Lang.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    attribute :agent_ids, {:array, :string} do
      allow_nil?(false)
      default([])
    end

    attribute(:task_type, :atom)
    attribute(:task_goal, :string)
    attribute(:strategy, :atom)

    attribute(:results_total, :integer, default: 0)
    attribute(:results_success, :integer, default: 0)
    attribute(:results_errors, :integer, default: 0)

    attribute(:winner, :string)
    attribute(:summary, :map, default: %{})
    attribute(:context, :map, default: %{})

    timestamps()
  end

  actions do
    defaults([:read])

    create :record do
      argument(:agent_ids, {:array, :string}, allow_nil?: false)
      argument(:task, :map, default: %{})
      argument(:merged, :map, default: %{})
      argument(:winner, :string)
      argument(:context, :map, default: %{})

      change(fn changeset, _ctx ->
        task = Ash.Changeset.get_argument(changeset, :task) || %{}
        merged = Ash.Changeset.get_argument(changeset, :merged) || %{}
        winner = Ash.Changeset.get_argument(changeset, :winner)
        agent_ids = Ash.Changeset.get_argument(changeset, :agent_ids) || []

        totals = Map.get(merged, :totals, merged)

        changeset
        |> Ash.Changeset.change_attribute(:agent_ids, agent_ids)
        |> Ash.Changeset.change_attribute(:task_type, Map.get(task, :type))
        |> Ash.Changeset.change_attribute(:task_goal, Map.get(task, :goal))
        |> Ash.Changeset.change_attribute(:strategy, Map.get(task, :strategy))
        |> Ash.Changeset.change_attribute(:results_total, Map.get(totals, :total, 0))
        |> Ash.Changeset.change_attribute(:results_success, Map.get(totals, :success, 0))
        |> Ash.Changeset.change_attribute(:results_errors, Map.get(totals, :errors, 0))
        |> Ash.Changeset.change_attribute(:winner, winner)
        |> Ash.Changeset.change_attribute(:summary, merged)
        |> Ash.Changeset.change_attribute(
          :context,
          Ash.Changeset.get_argument(changeset, :context) || %{}
        )
      end)
    end

    read :recent do
      argument(:limit, :integer, default: 20)
      prepare(build(sort: [inserted_at: :desc], limit: arg(:limit)))
    end
  end

  # Convenience wrapper (safe): attempts DB write; returns {:ok, record} or {:error, reason}
  def record(agent_ids, task, merged, opts \\ %{}) do
    args = %{
      agent_ids: Enum.map(agent_ids, &to_string/1),
      task: task,
      merged: merged,
      winner: Map.get(merged, :winner) || Map.get(opts, :winner),
      context: Map.get(opts, :context, %{})
    }

    try do
      __MODULE__
      |> Ash.Changeset.for_create(:record, args)
      |> Ash.create()
    rescue
      _ -> {:error, :coordination_summary_persist_failed}
    end
  end

  def recent(limit \\ 20) do
    __MODULE__
    |> Ash.Query.for_read(:recent, %{limit: limit})
    |> Ash.read()
  end
end
