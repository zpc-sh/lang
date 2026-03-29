defmodule Lang.Tokens.Request do
  @moduledoc """
  Token optimization request for LSP methods under `lang.tokens.*`.

  Handles requests for token estimation, compression, filtering, streaming,
  and caching strategy optimization.
  """

  use Ash.Resource,
    domain: Lang.Tokens,
    data_layer: AshPostgres.DataLayer

  alias Lang.Analyses.{Run, File}
  alias Lang.Accounts.User
  alias Lang.Analyses.Project

  postgres do
    table("token_requests")
    repo(Lang.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    attribute :kind, :atom do
      allow_nil?(false)

      constraints(
        one_of: [
          :estimate,
          :compress,
          :filter,
          :stream,
          :cache_strategy
        ]
      )
    end

    attribute :input, :map do
      allow_nil?(false)
      default(%{})
      description("Input parameters for token optimization operation")
    end

    attribute :model_type, :string do
      allow_nil?(true)
      description("Target model type for tokenization (gpt-4, claude-3, etc.)")
    end

    attribute :target_ratio, :decimal do
      allow_nil?(true)
      description("Target compression ratio (0.1-1.0) for compression operations")
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
      description("Additional metadata for the optimization request")
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
        :input,
        :model_type,
        :target_ratio,
        :user_id,
        :project_id,
        :run_id,
        :metadata
      ])

      validate(present([:kind]))
      change(set_attribute(:status, :pending))
    end

    create :create_enqueued do
      accept([
        :kind,
        :input,
        :model_type,
        :target_ratio,
        :user_id,
        :project_id,
        :run_id,
        :metadata
      ])

      validate(present([:kind]))
      change(set_attribute(:status, :pending))

      change(fn changeset, _ ->
        Ash.Changeset.after_action(changeset, fn _cs, req ->
          %{"request_id" => req.id}
          |> Lang.Tokens.Workers.RequestWorker.new(queue: :analysis)
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
  end
end
