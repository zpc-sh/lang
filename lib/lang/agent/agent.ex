defmodule Lang.Agent.Agent do
  @moduledoc """
  Agent resource for managing AI agent entities with capabilities, state, and security tracking.

  Agents are the core entities in LANG's cognitive operating system, representing
  specialized AI workers with defined capabilities and security profiles.
  """

  use Ash.Resource,
    domain: Lang.Agent,
    data_layer: AshPostgres.DataLayer

  # Needed to use Ash.Query macros (filter/2 with ^ pins)
  require Ash.Query

  postgres do
    table("agents")
    repo(Lang.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    attribute :name, :string do
      allow_nil?(false)
      description("Human-readable name for the agent")
    end

    attribute :capabilities, {:array, :atom} do
      allow_nil?(false)
      default([])
      description("List of capabilities this agent possesses")
    end

    attribute :capability_track, :atom do
      allow_nil?(false)
      default(:track_1)
      description("Capability track: :track_1, :track_2, :track_3, :track_4")
      constraints(one_of: [:track_1, :track_2, :track_3, :track_4])
    end

    attribute :constraints, :map do
      allow_nil?(false)
      default(%{})
      description("Resource limits and operational constraints")
    end

    attribute :state, :atom do
      allow_nil?(false)
      default(:spawning)
      description("Current agent state")
      constraints(one_of: [:spawning, :active, :idle, :quarantined, :terminated])
    end

    attribute :trust_score, :decimal do
      allow_nil?(false)
      default(Decimal.new("1.0"))
      description("Trust score from 0.0 to 1.0")
      constraints(min: 0.0, max: 1.0)
    end

    attribute :behavior_profile, :map do
      allow_nil?(false)
      default(%{})
      description("Behavioral baseline for rogue detection")
    end

    attribute :cognitive_load, :decimal do
      allow_nil?(false)
      default(Decimal.new("0.0"))
      description("Current cognitive load from 0.0 to 1.0")
      constraints(min: 0.0, max: 1.0)
    end

    attribute :resource_usage, :map do
      allow_nil?(false)
      default(%{})
      description("Current resource usage tracking")
    end

    attribute :sandbox_config, :map do
      allow_nil?(false)
      default(%{enabled: true, filesystem_root: nil, token_limit: 10_000})
      description("Sandbox configuration for security")
    end

    attribute :session_id, :string do
      description("Associated session workspace ID")
    end

    attribute :parent_agent_id, :uuid do
      description("ID of parent agent if this is a spawned sub-agent")
    end

    attribute :spawned_by, :string do
      description("What/who spawned this agent (user, system, agent)")
    end

    attribute :metadata, :map do
      allow_nil?(false)
      default(%{})
      description("Additional metadata and configuration")
    end

    timestamps()
  end

  relationships do
    belongs_to :parent_agent, __MODULE__ do
      source_attribute(:parent_agent_id)
      destination_attribute(:id)
    end

    has_many :child_agents, __MODULE__ do
      source_attribute(:id)
      destination_attribute(:parent_agent_id)
    end

    has_many :behavioral_samples, Lang.Agent.BehavioralSample do
      source_attribute(:id)
      destination_attribute(:agent_id)
    end
  end

  actions do
    defaults([:read, :destroy])

    # Ash v3 explicit read actions with baked-in filters
    read :read_by_id do
      description("Read a single agent by id")
      get? true
      argument(:id, :uuid, allow_nil?: false)
      prepare(build(filter: expr(id == ^arg(:id))))
    end

    read :list_active do
      description("List all active agents")
      prepare(build(filter: expr(state == :active)))
    end

    read :list_by_session do
      description("List agents by session id")
      argument(:session_id, :string, allow_nil?: false)
      prepare(build(filter: expr(session_id == ^arg(:session_id))))
    end

    create :spawn do
      description("Spawn a new agent with capabilities and constraints")

      argument(:capabilities, {:array, :atom}, allow_nil?: false)
      argument(:constraints, :map, default: %{})
      argument(:session_id, :string)
      argument(:spawned_by, :string, default: "system")
      argument(:sandbox_config, :map, default: %{})
      argument(:metadata, :map, default: %{})

      change(fn changeset, _context ->
        capabilities = Ash.Changeset.get_argument(changeset, :capabilities)
        track = determine_capability_track(capabilities)

        changeset
        |> Ash.Changeset.change_attribute(:name, generate_agent_name())
        |> Ash.Changeset.change_attribute(:capabilities, capabilities)
        |> Ash.Changeset.change_attribute(:capability_track, track)
        |> Ash.Changeset.change_attribute(
          :constraints,
          Ash.Changeset.get_argument(changeset, :constraints)
        )
        |> Ash.Changeset.change_attribute(
          :session_id,
          Ash.Changeset.get_argument(changeset, :session_id)
        )
        |> Ash.Changeset.change_attribute(
          :spawned_by,
          Ash.Changeset.get_argument(changeset, :spawned_by)
        )
        |> Ash.Changeset.change_attribute(
          :sandbox_config,
          merge_sandbox_config(Ash.Changeset.get_argument(changeset, :sandbox_config))
        )
        |> Ash.Changeset.change_attribute(
          :metadata,
          Ash.Changeset.get_argument(changeset, :metadata)
        )
        |> Ash.Changeset.change_attribute(:state, :active)
      end)

      change(after_action(&track_spawn_event/2))
    end

    update :activate do
      description("Activate a spawned agent")
      require_atomic? false
      change(set_attribute(:state, :active))
    end

    update :quarantine do
      description("Quarantine a potentially rogue agent")
      require_atomic? false

      argument(:reason, :string, allow_nil?: false)
      argument(:severity, :atom, default: :medium)

      change(fn changeset, _context ->
        reason = Ash.Changeset.get_argument(changeset, :reason)
        severity = Ash.Changeset.get_argument(changeset, :severity)

        quarantine_metadata = %{
          quarantined_at: DateTime.utc_now(),
          quarantine_reason: reason,
          quarantine_severity: severity
        }

        changeset
        |> Ash.Changeset.change_attribute(:state, :quarantined)
        |> Ash.Changeset.change_attribute(:trust_score, Decimal.new("0.0"))
        |> Ash.Changeset.update_attribute(:metadata, fn metadata ->
          Map.merge(metadata, quarantine_metadata)
        end)
      end)

      change(after_action(&track_quarantine_event/2))
    end

    update :update_trust_score do
      description("Update agent trust score based on behavior")
      require_atomic? false

      argument(:new_score, :decimal, allow_nil?: false)
      argument(:reason, :string)

      change(fn changeset, _context ->
        new_score = Ash.Changeset.get_argument(changeset, :new_score)
        reason = Ash.Changeset.get_argument(changeset, :reason)

        # Clamp score between 0.0 and 1.0
        clamped_score =
          new_score
          |> Decimal.max(Decimal.new("0.0"))
          |> Decimal.min(Decimal.new("1.0"))

        trust_update = %{
          updated_at: DateTime.utc_now(),
          reason: reason,
          previous_score: changeset.data.trust_score,
          new_score: clamped_score
        }

        changeset
        |> Ash.Changeset.change_attribute(:trust_score, clamped_score)
        |> Ash.Changeset.update_attribute(:metadata, fn metadata ->
          trust_history = Map.get(metadata, :trust_history, [])
          Map.put(metadata, :trust_history, [trust_update | Enum.take(trust_history, 9)])
        end)
      end)
    end

    update :update_cognitive_load do
      description("Update current cognitive load")
      require_atomic? false

      argument(:load, :decimal, allow_nil?: false)

      change(fn changeset, _context ->
        load = Ash.Changeset.get_argument(changeset, :load)

        clamped_load =
          load
          |> Decimal.max(Decimal.new("0.0"))
          |> Decimal.min(Decimal.new("1.0"))

        Ash.Changeset.change_attribute(changeset, :cognitive_load, clamped_load)
      end)
    end

    update :track_resource_usage do
      description("Track resource usage for this agent")
      require_atomic? false

      argument(:resource_type, :atom, allow_nil?: false)
      argument(:amount, :integer, allow_nil?: false)

      change(fn changeset, _context ->
        resource_type = Ash.Changeset.get_argument(changeset, :resource_type)
        amount = Ash.Changeset.get_argument(changeset, :amount)

        Ash.Changeset.update_attribute(changeset, :resource_usage, fn usage ->
          current = Map.get(usage, resource_type, 0)
          Map.put(usage, resource_type, current + amount)
        end)
      end)
    end

    update :terminate do
      description("Terminate agent and clean up resources")
      require_atomic? false

      argument(:reason, :string, default: "normal")

      change(fn changeset, _context ->
        reason = Ash.Changeset.get_argument(changeset, :reason)

        termination_data = %{
          terminated_at: DateTime.utc_now(),
          termination_reason: reason
        }

        changeset
        |> Ash.Changeset.change_attribute(:state, :terminated)
        |> Ash.Changeset.update_attribute(:metadata, fn metadata ->
          Map.merge(metadata, termination_data)
        end)
      end)

      change(after_action(&track_termination_event/2))
    end
  end

  aggregates do
    count(:child_agent_count, :child_agents)

    count :active_child_count, :child_agents do
      filter(expr(state == :active))
    end

    first :latest_behavioral_sample, :behavioral_samples, :inserted_at do
      sort(inserted_at: :desc)
    end
  end

  calculations do
    calculate(:is_trusted, :boolean, expr(trust_score >= 0.5))
    calculate(:is_overloaded, :boolean, expr(cognitive_load >= 0.8))
    calculate(:is_operational, :boolean, expr(state in [:active, :idle]))

    calculate :capability_level, :integer do
      calculation(fn records, _context ->
        Enum.map(records, fn record ->
          case record.capability_track do
            :track_1 -> 1
            :track_2 -> 2
            :track_3 -> 3
            :track_4 -> 4
          end
        end)
      end)
    end
  end

  validations do
    validate(present([:name, :capabilities, :capability_track]))

    validate(fn changeset, _context ->
      capabilities = Ash.Changeset.get_attribute(changeset, :capabilities)
      track = Ash.Changeset.get_attribute(changeset, :capability_track)

      if valid_capabilities_for_track?(capabilities, track) do
        :ok
      else
        {:error, field: :capabilities, message: "Invalid capabilities for track #{track}"}
      end
    end)
  end

  # code_interface disabled temporarily for Ash v3 DSL migration

  # --- Ash v3 wrapper functions (replacing code_interface usage) ---
  def read_by_id(id) do
    __MODULE__
    |> Ash.Query.filter(id == ^id)
    |> Ash.read_one()
  end

  def list_active do
    __MODULE__
    |> Ash.Query.filter(state == :active)
    |> Ash.read()
  end

  def list_by_session(session_id) do
    __MODULE__
    |> Ash.Query.filter(session_id == ^session_id)
    |> Ash.read()
  end

  def spawn(attrs) when is_map(attrs) do
    __MODULE__
    |> Ash.Changeset.for_create(:spawn, attrs)
    |> Ash.create()
  end

  def activate(agent, attrs \\ %{}) do
    agent
    |> Ash.Changeset.for_update(:activate, attrs)
    |> Ash.update()
  end

  def terminate(agent, attrs \\ %{}) do
    agent
    |> Ash.Changeset.for_update(:terminate, attrs)
    |> Ash.update()
  end

  def quarantine(agent, attrs \\ %{}) do
    agent
    |> Ash.Changeset.for_update(:quarantine, attrs)
    |> Ash.update()
  end

  # Private helper functions
  defp determine_capability_track(capabilities) do
    cond do
      Enum.any?(capabilities, &(&1 in [:architecture_changes, :system_wide])) -> :track_4
      Enum.any?(capabilities, &(&1 in [:multi_file_coordination, :refactoring])) -> :track_3
      Enum.any?(capabilities, &(&1 in [:single_file_edit, :local_generation])) -> :track_2
      true -> :track_1
    end
  end

  defp valid_capabilities_for_track?(capabilities, track) do
    valid_caps =
      case track do
        :track_1 ->
          [:read_only, :analysis, :explain]

        :track_2 ->
          [:read_only, :analysis, :explain, :single_file_edit, :local_generation]

        :track_3 ->
          [
            :read_only,
            :analysis,
            :explain,
            :single_file_edit,
            :local_generation,
            :multi_file_coordination,
            :refactoring
          ]

        :track_4 ->
          [
            :read_only,
            :analysis,
            :explain,
            :single_file_edit,
            :local_generation,
            :multi_file_coordination,
            :refactoring,
            :architecture_changes,
            :system_wide
          ]
      end

    Enum.all?(capabilities, &(&1 in valid_caps))
  end

  defp generate_agent_name do
    adjectives = ["Swift", "Clever", "Bright", "Quick", "Sharp", "Keen", "Wise", "Alert"]
    nouns = ["Agent", "Worker", "Assistant", "Analyzer", "Scanner", "Builder", "Coordinator"]

    adjective = Enum.random(adjectives)
    noun = Enum.random(nouns)
    number = :rand.uniform(999)

    "#{adjective}#{noun}#{number}"
  end

  defp merge_sandbox_config(user_config) do
    default_config = %{
      enabled: true,
      filesystem_root: nil,
      token_limit: 10_000,
      memory_limit_mb: 512,
      cpu_limit_percent: 25,
      network_access: false
    }

    Map.merge(default_config, user_config || %{})
  end

  # Event tracking helpers
  defp track_spawn_event(changeset, agent) do
    Lang.Events.Agent.track_spawn(
      agent.id,
      agent.capabilities,
      agent.constraints,
      %{
        session_id: agent.session_id,
        spawned_by: agent.spawned_by,
        capability_track: agent.capability_track
      }
    )

    {:ok, agent}
  end

  defp track_quarantine_event(changeset, agent) do
    reason = get_in(agent.metadata, ["quarantine_reason"]) || "unknown"
    severity = get_in(agent.metadata, ["quarantine_severity"]) || :medium

    Lang.Events.Agent.track_quarantine(
      "system",
      agent.id,
      reason,
      %{isolation: true, resource_limits: agent.constraints},
      %{severity: severity}
    )

    {:ok, agent}
  end

  defp track_termination_event(changeset, agent) do
    reason = get_in(agent.metadata, ["termination_reason"]) || "unknown"

    Lang.Events.Agent.track_termination(
      agent.id,
      reason,
      agent.state,
      %{
        final_trust_score: agent.trust_score,
        cognitive_load: agent.cognitive_load,
        resource_usage: agent.resource_usage
      }
    )

    {:ok, agent}
  end

end
