defmodule Lang.Query.Request do
  @moduledoc """
  Natural language query request for LSP methods under `lang.query.*`.

  Handles requests for natural language code queries, impact analysis,
  dependency analysis, and code ownership tracking. Integrates with
  existing GraphReasoner, provider implementations, and dependency
  analysis capabilities.
  """

  use Ash.Resource,
    domain: Lang.Query,
    data_layer: AshPostgres.DataLayer

  alias Lang.Analyses.{Run, File}
  alias Lang.Accounts.User
  alias Lang.Analyses.Project

  postgres do
    table("query_requests")
    repo(Lang.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    attribute :kind, :atom do
      allow_nil?(false)

      constraints(
        one_of: [
          :natural,
          :impact,
          :dependency,
          :ownership
        ]
      )
    end

    attribute :query, :string do
      allow_nil?(false)
      description("The natural language query or target element to analyze")
    end

    attribute :context, :map do
      allow_nil?(false)
      default(%{})
      description("Query context including code, scope, files, etc.")
    end

    attribute :scope, :string do
      allow_nil?(true)
      description("Query scope: 'file', 'module', 'project', 'global'")
    end

    attribute :target_element, :string do
      allow_nil?(true)
      description("Specific code element for impact/dependency analysis")
    end

    attribute :change_description, :string do
      allow_nil?(true)
      description("Description of proposed change for impact analysis")
    end

    attribute :analysis_depth, :atom do
      allow_nil?(false)
      default(:standard)
      constraints(one_of: [:shallow, :standard, :deep])
      description("Depth of analysis to perform")
    end

    attribute :use_graph_reasoning, :boolean do
      allow_nil?(false)
      default(true)
      description("Whether to use graph reasoning for enhanced analysis")
    end

    attribute :provider_preference, :string do
      allow_nil?(true)
      description("Preferred AI provider: 'openai', 'anthropic', 'xai'")
    end

    attribute :status, :atom do
      allow_nil?(false)
      default(:pending)
      constraints(one_of: [:pending, :running, :completed, :failed, :cancelled])
    end

    attribute :error_message, :string do
      allow_nil?(true)
    end

    attribute :metadata, :map do
      allow_nil?(false)
      default(%{})
      description("Additional metadata for the query request")
    end

    attribute :started_at, :utc_datetime do
      allow_nil?(true)
    end

    attribute :completed_at, :utc_datetime do
      allow_nil?(true)
    end

    create_timestamp(:inserted_at)
    update_timestamp(:updated_at)
  end

  relationships do
    belongs_to :user, User do
      attribute_writable?(true)
    end

    belongs_to :project, Project do
      attribute_writable?(true)
    end

    belongs_to :run, Run do
      attribute_writable?(true)
    end
  end

  actions do
    defaults([:read])

    create :create do
      accept([
        :kind,
        :query,
        :context,
        :scope,
        :target_element,
        :change_description,
        :analysis_depth,
        :use_graph_reasoning,
        :provider_preference,
        :user_id,
        :project_id,
        :run_id,
        :metadata
      ])

      validate(present([:kind, :query]))
      change(set_attribute(:status, :pending))
    end

    create :create_enqueued do
      accept([
        :kind,
        :query,
        :context,
        :scope,
        :target_element,
        :change_description,
        :analysis_depth,
        :use_graph_reasoning,
        :provider_preference,
        :user_id,
        :project_id,
        :run_id,
        :metadata
      ])

      validate(present([:kind, :query]))
      change(set_attribute(:status, :pending))

      change(fn changeset, _ ->
        Ash.Changeset.after_action(changeset, fn _cs, req ->
          %{"request_id" => req.id}
          |> Lang.Query.Workers.RequestWorker.new(queue: :analysis)
          |> Oban.insert()

          {:ok, req}
        end)
      end)
    end

    update :update_status do
      accept([:error_message, :metadata])
      argument(:status, :atom, allow_nil?: false)
      validate(one_of(:status, [:pending, :running, :completed, :failed, :cancelled]))

      change(fn changeset, ctx ->
        status = ctx.arguments[:status]
        changeset = Ash.Changeset.change_attribute(changeset, :status, status)

        case status do
          :running ->
            Ash.Changeset.change_attribute(changeset, :started_at, DateTime.utc_now())

          :completed ->
            Ash.Changeset.change_attribute(changeset, :completed_at, DateTime.utc_now())

          :failed ->
            Ash.Changeset.change_attribute(changeset, :completed_at, DateTime.utc_now())

          :cancelled ->
            Ash.Changeset.change_attribute(changeset, :completed_at, DateTime.utc_now())

          _ ->
            changeset
        end
      end)
    end

    update :complete do
      accept([:metadata])

      change(fn changeset, _ ->
        changeset
        |> Ash.Changeset.change_attribute(:status, :completed)
        |> Ash.Changeset.change_attribute(:completed_at, DateTime.utc_now())
      end)
    end

    update :fail do
      accept([:error_message, :metadata])
      validate(present(:error_message))

      change(fn changeset, _ ->
        changeset
        |> Ash.Changeset.change_attribute(:status, :failed)
        |> Ash.Changeset.change_attribute(:completed_at, DateTime.utc_now())
      end)
    end

    update :cancel do
      accept([:metadata])

      change(fn changeset, _ ->
        changeset
        |> Ash.Changeset.change_attribute(:status, :cancelled)
        |> Ash.Changeset.change_attribute(:completed_at, DateTime.utc_now())
      end)
    end
  end

  code_interface do
    define(:read_all, action: :read)
    define(:by_id, action: :read, get_by: [:id])
    define(:create, action: :create)
    define(:create_enqueued, action: :create_enqueued)
    define(:update_status, action: :update_status)
    define(:complete, action: :complete)
    define(:fail, action: :fail)
    define(:cancel, action: :cancel)
  end

  calculations do
    calculate(
      :duration_ms,
      :integer,
      expr(fragment("EXTRACT(EPOCH FROM (? - ?)) * 1000", completed_at, started_at))
    )

    calculate(
      :has_context,
      :boolean,
      expr(fragment("jsonb_array_length(COALESCE(?, '{}'::jsonb)) > 0", context))
    )
  end
end
