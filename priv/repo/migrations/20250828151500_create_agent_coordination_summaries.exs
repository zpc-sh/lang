defmodule Lang.Repo.Migrations.CreateAgentCoordinationSummaries do
  use Ecto.Migration

  def change do
    create table(:agent_coordination_summaries, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :agent_ids, {:array, :string}, null: false, default: []
      add :task_type, :string
      add :task_goal, :text
      add :strategy, :string
      add :results_total, :integer, default: 0, null: false
      add :results_success, :integer, default: 0, null: false
      add :results_errors, :integer, default: 0, null: false
      add :winner, :string
      add :summary, :map, default: %{}
      add :context, :map, default: %{}

      timestamps()
    end

    create index(:agent_coordination_summaries, [:inserted_at])
    create index(:agent_coordination_summaries, [:strategy])
    create index(:agent_coordination_summaries, [:task_type])
  end
end

