defmodule Lang.Workspace.WorkingSet do
  @moduledoc """
  The active working context for an agent in a workspace.
  Not about auth/sessions - just the current focus area.
  """
  use Ash.Resource,
    domain: Lang.Workspaces,
    data_layer: Lang.Ash.RedisDataLayer

  attributes do
    uuid_primary_key(:id)

    attribute :workspace_id, :uuid do
      allow_nil?(false)
    end

    attribute :agent_id, :string do
      allow_nil?(false)
    end

    # What the agent is currently working with
    attribute :active_symbols, {:array, :uuid} do
      default([])
    end

    attribute :active_files, {:array, :string} do
      default([])
    end

    attribute :focus_area, :map do
      description("Current area of focus - could be a function, module, etc")
    end

    # Learned patterns in this working set
    attribute :discovered_patterns, {:array, :map} do
      default([])
    end

    # Performance metrics
    attribute :tokens_processed, :integer do
      default(0)
    end

    attribute :tokens_saved, :integer do
      default(0)
    end

    attribute(:optimization_rate, :float)

    attribute(:last_updated, :utc_datetime_usec)
  end

  relationships do
    belongs_to :workspace, Lang.Workspace.Workspace, domain: Lang.Workspaces
    has_many :fragments, Lang.Workspace.Fragment

    many_to_many :symbols, Lang.Workspace.Symbol do
      through(Lang.Workspace.WorkingSetSymbol)
    end
  end

  actions do
    defaults([:create, :read, :update, :destroy])

    update :add_symbol_to_working_set do
      argument(:symbol_id, :uuid, allow_nil?: false)

      change(fn changeset, context ->
        current_symbols = Ash.Changeset.get_attribute(changeset, :active_symbols) || []
        new_symbols = Enum.uniq([context.arguments.symbol_id | current_symbols])

        changeset
        |> Ash.Changeset.change_attribute(:active_symbols, new_symbols)
        |> Ash.Changeset.change_attribute(:last_updated, DateTime.utc_now())
      end)
    end

    update :add_file_to_working_set do
      argument(:file_path, :string, allow_nil?: false)

      change(fn changeset, context ->
        current_files = Ash.Changeset.get_attribute(changeset, :active_files) || []
        new_files = Enum.uniq([context.arguments.file_path | current_files])

        changeset
        |> Ash.Changeset.change_attribute(:active_files, new_files)
        |> Ash.Changeset.change_attribute(:last_updated, DateTime.utc_now())
      end)
    end

    update :record_optimization do
      argument(:tokens_before, :integer)
      argument(:tokens_after, :integer)

      change(fn changeset, context ->
        saved = context.arguments.tokens_before - context.arguments.tokens_after
        total_saved = Ash.Changeset.get_attribute(changeset, :tokens_saved) + saved

        total_processed =
          Ash.Changeset.get_attribute(changeset, :tokens_processed) +
            context.arguments.tokens_before

        optimization_rate =
          if total_processed > 0 do
            total_saved / total_processed
          else
            0.0
          end

        changeset
        |> Ash.Changeset.change_attribute(:tokens_saved, total_saved)
        |> Ash.Changeset.change_attribute(:tokens_processed, total_processed)
        |> Ash.Changeset.change_attribute(:optimization_rate, optimization_rate)
        |> Ash.Changeset.change_attribute(:last_updated, DateTime.utc_now())
      end)

      # Broadcast significant optimizations
      after_action(fn result, context ->
        working_set = result.result

        if working_set.optimization_rate >= 0.5 do
          Lang.Workspace.ChatMessage.broadcast!(
            :optimization,
            %{
              agent_id: working_set.agent_id,
              achievement: "50% optimization rate reached",
              tokens_saved: working_set.tokens_saved,
              optimization_rate: working_set.optimization_rate
            }
          )
        end

        {:ok, result}
      end)
    end

    update :set_focus_area do
      accept([:focus_area])

      change(fn changeset, _context ->
        Ash.Changeset.change_attribute(changeset, :last_updated, DateTime.utc_now())
      end)
    end

    update :add_discovered_pattern do
      argument(:pattern, :map, allow_nil?: false)

      change(fn changeset, context ->
        current_patterns = Ash.Changeset.get_attribute(changeset, :discovered_patterns) || []
        new_patterns = [context.arguments.pattern | current_patterns]

        changeset
        |> Ash.Changeset.change_attribute(:discovered_patterns, new_patterns)
        |> Ash.Changeset.change_attribute(:last_updated, DateTime.utc_now())
      end)
    end
  end

  code_interface do
    define(:create_working_set, action: :create)
    define(:add_symbol, action: :add_symbol_to_working_set, args: [:symbol_id])
    define(:add_file, action: :add_file_to_working_set, args: [:file_path])

    define(:record_token_savings,
      action: :record_optimization,
      args: [:tokens_before, :tokens_after]
    )

    define(:set_focus, action: :set_focus_area)
    define(:add_pattern, action: :add_discovered_pattern, args: [:pattern])
  end

  # Redis configuration
  # Working sets expire after 2 hours of inactivity
  attributes do
    attribute(:ttl, :integer, public?: false, default: 7200)
  end

  identities do
    identity(:by_workspace_and_agent, [:workspace_id, :agent_id])
  end
end
