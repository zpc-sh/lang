defmodule Lang.Events.UserActivityEvent do
  @moduledoc """
  Event for tracking user activity across the platform.

  Captures user interactions, sessions, and behavioral patterns
  for analytics and user experience optimization.
  """

  use Ash.Resource,
    domain: Lang.Events,
    extensions: [AshPostgres.DataLayer]

  postgres do
    table("user_activity_events")
    repo(Lang.Repo)
  end

  attributes do
    uuid_primary_key(:id)

    # User and organization context
    attribute(:user_id, :uuid, allow_nil?: false)
    attribute(:organization_id, :uuid, allow_nil?: false)

    # Activity details
    attribute(:activity_type, :atom, allow_nil?: false)
    attribute(:activity_name, :string)
    attribute(:category, :string)

    # Session tracking
    attribute(:session_id, :string)
    attribute(:session_duration_ms, :integer)

    # Page/feature tracking
    attribute(:page_url, :string)
    attribute(:page_title, :string)
    attribute(:referrer_url, :string)
    attribute(:feature_used, :string)

    # User interaction details
    attribute(:action_taken, :string)
    attribute(:target_element, :string)
    attribute(:interaction_data, :map, default: %{})

    # Device and browser info
    attribute(:user_agent, :string)
    attribute(:browser_name, :string)
    attribute(:browser_version, :string)
    attribute(:device_type, :string)
    attribute(:platform, :string)
    attribute(:screen_resolution, :string)

    # Location and network
    attribute(:ip_address, :string)
    attribute(:country_code, :string)
    attribute(:timezone, :string)

    # Performance metrics
    attribute(:page_load_time_ms, :integer)
    attribute(:time_on_page_ms, :integer)
    attribute(:scroll_depth_percent, :integer)

    # Engagement metrics
    attribute(:clicks_count, :integer, default: 0)
    attribute(:keystrokes_count, :integer, default: 0)
    attribute(:mouse_movements, :integer, default: 0)

    # A/B testing and experiments
    attribute(:experiment_id, :string)
    attribute(:variant_id, :string)
    attribute(:conversion_goal, :string)
    attribute(:converted, :boolean, default: false)

    # Additional metadata
    attribute(:metadata, :map, default: %{})

    timestamps()
  end

  # Relationships
  relationships do
    belongs_to(:user, Lang.Accounts.User)
    belongs_to(:organization, Lang.Accounts.Organization)
  end

  actions do
    defaults([:read])

    create :log_activity do
      accept([
        :user_id,
        :organization_id,
        :activity_type,
        :activity_name,
        :category,
        :session_id,
        :session_duration_ms,
        :page_url,
        :page_title,
        :referrer_url,
        :feature_used,
        :action_taken,
        :target_element,
        :interaction_data,
        :user_agent,
        :browser_name,
        :browser_version,
        :device_type,
        :platform,
        :screen_resolution,
        :ip_address,
        :country_code,
        :timezone,
        :page_load_time_ms,
        :time_on_page_ms,
        :scroll_depth_percent,
        :clicks_count,
        :keystrokes_count,
        :mouse_movements,
        :experiment_id,
        :variant_id,
        :conversion_goal,
        :converted,
        :metadata
      ])
    end

    read :by_user do
      argument(:user_id, :uuid, allow_nil?: false)
      filter(expr(user_id == ^arg(:user_id)))
    end

    read :by_session do
      argument(:session_id, :string, allow_nil?: false)
      filter(expr(session_id == ^arg(:session_id)))
    end

    read :by_activity_type do
      argument(:activity_type, :atom, allow_nil?: false)
      filter(expr(activity_type == ^arg(:activity_type)))
    end

    read :recent_activity do
      argument(:limit, :integer, default: 50)

      pagination do
        default_limit(50)
        max_page_size(100)
        offset?(true)
      end

      prepare(build(sort: [inserted_at: :desc]))
    end

    read :active_sessions do
      # Sessions active in the last 30 minutes
      filter(expr(inserted_at > ago(30, :minute)))
      filter(expr(activity_type in [:page_view, :interaction, :heartbeat]))
    end

    read :conversions do
      filter(expr(converted == true))
    end

    read :by_date_range do
      argument(:start_date, :utc_datetime, allow_nil?: false)
      argument(:end_date, :utc_datetime, allow_nil?: false)
      filter(expr(inserted_at >= ^arg(:start_date) and inserted_at <= ^arg(:end_date)))
    end
  end

  # Calculations
  calculations do
    calculate(:date, :date, expr(fragment("date(?)", inserted_at)))
    calculate(:hour_of_day, :integer, expr(fragment("extract(hour from ?)", inserted_at)))
    calculate(:day_of_week, :integer, expr(fragment("extract(dow from ?)", inserted_at)))
    calculate(:is_mobile, :boolean, expr(device_type == "mobile"))
    calculate(:is_conversion, :boolean, expr(converted == true))
  end

  # Aggregates for analytics
  aggregates do
    count(:total_activities, :id)
    count(:unique_sessions, :session_id, uniq?: true)
  end

  # Code interface
  code_interface do
    domain(Lang.Events)
    define(:log_activity)
    define(:by_user, args: [:user_id])
    define(:by_session, args: [:session_id])
    define(:recent_activity, args: [:limit])
    define(:active_sessions)
    define(:conversions)
  end

  # Convenience functions
  def track_page_view(user_id, organization_id, page_url, opts \\ []) do
    attrs =
      Keyword.merge(
        [
          user_id: user_id,
          organization_id: organization_id,
          activity_type: :page_view,
          page_url: page_url
        ],
        opts
      )

    log_activity(attrs)
  end

  def track_feature_usage(user_id, organization_id, feature_name, opts \\ []) do
    attrs =
      Keyword.merge(
        [
          user_id: user_id,
          organization_id: organization_id,
          activity_type: :feature_usage,
          feature_used: feature_name
        ],
        opts
      )

    log_activity(attrs)
  end

  def track_conversion(user_id, organization_id, goal, opts \\ []) do
    attrs =
      Keyword.merge(
        [
          user_id: user_id,
          organization_id: organization_id,
          activity_type: :conversion,
          conversion_goal: goal,
          converted: true
        ],
        opts
      )

    log_activity(attrs)
  end

  def track_session_start(user_id, organization_id, session_id, opts \\ []) do
    attrs =
      Keyword.merge(
        [
          user_id: user_id,
          organization_id: organization_id,
          activity_type: :session_start,
          session_id: session_id
        ],
        opts
      )

    log_activity(attrs)
  end

  def track_session_end(user_id, organization_id, session_id, duration_ms, opts \\ []) do
    attrs =
      Keyword.merge(
        [
          user_id: user_id,
          organization_id: organization_id,
          activity_type: :session_end,
          session_id: session_id,
          session_duration_ms: duration_ms
        ],
        opts
      )

    log_activity(attrs)
  end
end
