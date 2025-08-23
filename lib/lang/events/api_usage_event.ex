defmodule Lang.Events.ApiUsageEvent do
  @moduledoc """
  Event for API usage tracking.

  Tracks all API usage across the platform for billing, rate limiting,
  and analytics purposes.
  """

  use Ash.Resource,
    domain: Lang.Events,
    extensions: [AshPostgres.DataLayer]

  postgres do
    table("api_usage_events")
    repo(Lang.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    # User and organization context
    attribute(:user_id, :uuid, allow_nil?: false)
    attribute(:organization_id, :uuid, allow_nil?: false)

    # Event details
    attribute(:operation_type, :atom, allow_nil?: false)
    attribute(:operation_name, :string)
    attribute(:content_format, :string)
    attribute(:content_size, :integer, default: 0)
    attribute(:processing_time_ms, :integer)

    # Request context
    attribute(:request_id, :string)
    attribute(:user_agent, :string)
    attribute(:ip_address, :string)
    attribute(:session_id, :string)

    # Performance metrics
    attribute(:response_time_ms, :integer)
    attribute(:memory_usage_mb, :float)
    attribute(:cpu_usage_percent, :float)

    # Error tracking
    attribute(:error_type, :string)
    attribute(:error_message, :string)
    attribute(:success, :boolean, default: true)

    # Rate limiting
    attribute(:rate_limited, :boolean, default: false)
    attribute(:rate_limit_type, :string)

    # Additional metadata
    attribute(:metadata, :map, default: %{})

    timestamps()
  end

  # Indexes
  identities do
    identity(:unique_request, [:request_id])
  end

  # Relationships
  relationships do
    belongs_to(:user, Lang.Accounts.User)
    belongs_to(:organization, Lang.Accounts.Organization)
  end

  actions do
    defaults([:read])

    create :log_usage do
      accept([
        :user_id,
        :organization_id,
        :operation_type,
        :operation_name,
        :content_format,
        :content_size,
        :processing_time_ms,
        :request_id,
        :user_agent,
        :ip_address,
        :session_id,
        :response_time_ms,
        :memory_usage_mb,
        :cpu_usage_percent,
        :error_type,
        :error_message,
        :success,
        :rate_limited,
        :rate_limit_type,
        :metadata
      ])
    end

    read :by_user do
      argument(:user_id, :uuid, allow_nil?: false)
      filter(expr(user_id == ^arg(:user_id)))
    end

    read :by_organization do
      argument(:organization_id, :uuid, allow_nil?: false)
      filter(expr(organization_id == ^arg(:organization_id)))
    end

    read :by_operation_type do
      argument(:operation_type, :atom, allow_nil?: false)
      filter(expr(operation_type == ^arg(:operation_type)))
    end

    read :recent do
      argument(:limit, :integer, default: 100)

      pagination do
        default_limit(100)
        max_page_size(1000)
        offset?(true)
      end

      prepare(build(sort: [inserted_at: :desc]))
    end

    read :monthly_stats do
      argument(:user_id, :uuid, allow_nil?: false)
      argument(:year_month, :string)
      filter(expr(user_id == ^arg(:user_id)))

      prepare(
        build(
          load: [:month_year],
          sort: [inserted_at: :desc]
        )
      )
    end

    read :errors_only do
      filter(expr(success == false))
    end
  end

  # Calculations
  calculations do
    calculate(:month_year, :string, expr(fragment("to_char(?, 'YYYY-MM')", inserted_at)))
    calculate(:hour_of_day, :integer, expr(fragment("extract(hour from ?)", inserted_at)))
  end

  # Note: Aggregates removed as they were incorrectly trying to count records in the same resource
  # Use queries with count() function instead for counting records

  # Code interface
  code_interface do
    domain(Lang.Events)
    define(:log_usage)
    define(:by_user, args: [:user_id])
    define(:by_organization, args: [:organization_id])
    define(:recent, args: [:limit])
    define(:monthly_stats, args: [:user_id, :year_month])
  end

  # Convenience functions
  def log_api_usage(user_id, operation_type, opts \\ []) do
    attrs =
      Keyword.merge(
        [
          user_id: user_id,
          operation_type: operation_type
        ],
        opts
      )

    log_usage(attrs)
  end

  def log_analysis_usage(user_id, format, content_size, processing_time, opts \\ []) do
    attrs =
      Keyword.merge(
        [
          user_id: user_id,
          operation_type: :text_analysis,
          content_format: format,
          content_size: content_size,
          processing_time_ms: processing_time
        ],
        opts
      )

    log_usage(attrs)
  end

  def current_month_count(user_id) do
    case monthly_stats(user_id, nil) do
      {:ok, events} -> {:ok, length(events)}
      error -> error
    end
  end

  def is_over_limit?(user, operation_count \\ 1) do
    case current_month_count(user.id) do
      {:ok, count} -> count + operation_count > user.organization.monthly_request_limit
      {:error, _} -> false
    end
  end
end
