defmodule Lang.Agent.Swarm do
  @moduledoc """
  Ash resource modeling an agent swarm lifecycle.

  Stores swarm metadata, goals, member agent ids, and status for auditing
  and orchestration tracking.
  """

  use Ash.Resource,
    domain: Lang.Agent,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJsonApi.Resource]

  require Ash.Query

  postgres do
    table("agent_swarms")
    repo(Lang.Repo)
  end

  json_api do
    type("agent_swarm")
    includes([:agents])

    routes do
      base("/api/v2/agent/swarms")
      get(:read)
      index(:read)
      # Read by alternate key via query param: /api/v2/agent/swarms/by_swarm_id?swarm_id=...
      get(:by_swarm_id, route: "/by_swarm_id")
      # Index by coordinator id: /api/v2/agent/swarms/by_coordinator?coordinator_id=...
      index(:by_coordinator, route: "/by_coordinator")
      # Index by any member agent's session_id: /api/v2/agent/swarms/by_session?session_id=...
      index(:by_session, route: "/by_session")
    end
  end

  attributes do
    uuid_primary_key(:id)

    attribute :swarm_id, :string do
      allow_nil?(false)
      description("External swarm id referenced by LSP")
    end

    attribute :goals, {:array, :string} do
      allow_nil?(false)
      default([])
      description("List of swarm goals")
    end

    attribute :agent_ids, {:array, :string} do
      allow_nil?(false)
      default([])
      description("Member agent ids (opaque identifiers)")
    end

    attribute :coordinator_id, :string do
      description("Optional coordinator agent id")
    end

    attribute :status, :atom do
      allow_nil?(false)
      default(:created)
      constraints(one_of: [:created, :provisioning, :active, :completed, :failed, :cancelled])
      description("Swarm lifecycle status")
    end

    attribute :metadata, :map do
      allow_nil?(false)
      default(%{})
      description("Additional JSON-LD compatible metadata")
    end

    timestamps()
  end

  actions do
    defaults([:read, :destroy])

    create :create do
      accept([:swarm_id, :goals, :agent_ids, :coordinator_id, :status, :metadata])
    end

    update :mark_provisioning do
      accept([])
      change(set_attribute(:status, :provisioning))
    end

    update :mark_active do
      accept([])
      change(set_attribute(:status, :active))
    end

    update :mark_completed do
      accept([])
      change(set_attribute(:status, :completed))
    end

    update :mark_failed do
      argument(:reason, :string)
      accept([])
      change(set_attribute(:status, :failed))
      change(fn changeset, _ctx ->
        meta = Ash.Changeset.get_attribute(changeset, :metadata) || %{}
        reason = Ash.Changeset.get_argument(changeset, :reason)
        Ash.Changeset.change_attribute(changeset, :metadata, Map.put(meta, "failed_reason", reason))
      end)
    end

    update :add_agents do
      argument(:agent_ids, {:array, :string}, allow_nil?: false)
      change(fn changeset, _ctx ->
        current = Ash.Changeset.get_attribute(changeset, :agent_ids) || []
        new_ids = Ash.Changeset.get_argument(changeset, :agent_ids) || []
        Ash.Changeset.change_attribute(changeset, :agent_ids, current ++ new_ids)
      end)
    end

    read :by_swarm_id do
      argument(:swarm_id, :string, allow_nil?: false)
      prepare(build(filter: expr(swarm_id == ^arg(:swarm_id))))
    end

    read :by_coordinator do
      argument(:coordinator_id, :string, allow_nil?: false)
      prepare(build(filter: expr(coordinator_id == ^arg(:coordinator_id))))
    end

    read :by_session do
      argument(:session_id, :string, allow_nil?: false)
      prepare(build(filter: expr(exists(agents, session_id == ^arg(:session_id)))) )
    end
  end

  relationships do
    has_many :agents, Lang.Agent.Agent do
      description("Agents provisioned under this swarm")
      destination_attribute(:swarm_id)
      public?(true)
    end
  end

  validations do
    validate present([:swarm_id])
    validate compare(:swarm_id, greater_than: 0)
  end
end
