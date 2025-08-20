defmodule Lang.Accounts.APIUsage do
  use Ash.Resource,
    otp_app: :lang,
    domain: Lang.Accounts,
    data_layer: AshPostgres.DataLayer,
    notifiers: [Ash.Notifier.PubSub],
    extensions: [AshOban]

  postgres do
    table("api_usage")
    repo(Lang.Repo)

    # Partition by month to keep individual partitions small
    custom_indexes do
      index([:user_id, :month_year])
      index([:operation_type, :inserted_at])
      index([:status, :inserted_at])
      # For cleanup queries
      index([:inserted_at])
    end
  end

  # AshOban configuration for background processing
  oban do
    triggers do
      # trigger :process_usage_metrics do
      #   debug?(true)
      #   queue(:metrics)
      #   action(:process_metrics)
      #   trigger_once?(true)

      #   # Process usage metrics in batches to avoid large resource issues
      #   worker_read_action(:unprocessed_metrics)
      #   worker_module_name(Lang.Accounts.APIUsage.AshOban.Worker.ProcessUsageMetrics)
      #   scheduler_module_name(Lang.Accounts.APIUsage.AshOban.Scheduler.ProcessUsageMetrics)
      # end

      # trigger :cleanup_old_usage do
      #   debug?(false)
      #   queue(:cleanup)
      #   action(:cleanup_old_records)

      #   # Note: Schedule configuration will be handled in application config
      #   worker_module_name(Lang.Accounts.APIUsage.AshOban.Worker.CleanupOldUsage)
      # end
    end
  end

  # PubSub configuration for real-time updates
  pub_sub do
    prefix("api_usage")
    module(LangWeb.Endpoint)

    # Transform data for pub_sub to keep messages small
    transform(fn usage ->
      %{
        id: usage.id,
        user_id: usage.user_id,
        operation_type: usage.operation_type,
        status: usage.status,
        month_year: usage.month_year,
        processing_time_ms: usage.processing_time_ms
      }
    end)

    # Publish to user-specific and global channels
    publish(:create, [:user_id])
    publish(:create, "global")
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:user_id, :uuid, allow_nil?: false, public?: true)
    attribute(:operation_type, :atom, allow_nil?: false, public?: true)
    attribute(:format, :string, public?: true)
    attribute(:content_size_bytes, :integer, public?: true)
    attribute(:processing_time_ms, :integer, public?: true)
    # :success, :error, :rate_limited
    attribute(:status, :atom, allow_nil?: false, public?: true)
    attribute(:error_type, :string, public?: true)
    attribute(:ip_address, :string, public?: true)
    attribute(:user_agent, :string, public?: true)
    attribute(:request_id, :string, public?: true)
    # Format: "2024-12"
    attribute(:month_year, :string, allow_nil?: false, public?: true)

    attribute :processed, :boolean do
      description("Whether this usage record has been processed for metrics aggregation")
      default(false)
      allow_nil?(false)
      public?(true)
    end

    timestamps()
  end

  actions do
    default_accept([
      :user_id,
      :operation_type,
      :format,
      :content_size_bytes,
      :processing_time_ms,
      :status,
      :error_type,
      :ip_address,
      :user_agent,
      :request_id,
      :month_year
    ])

    defaults([:read, :create, :destroy])

    create :log_usage do
      primary?(true)

      change(fn changeset, _context ->
        now = DateTime.utc_now()
        month_year = "#{now.year}-#{String.pad_leading(to_string(now.month), 2, "0")}"
        Ash.Changeset.change_attribute(changeset, :month_year, month_year)
      end)
    end

    # update :process_metrics do
    #   description("Process usage metrics in background")
    #   change(Lang.Accounts.APIUsage.Changes.ProcessMetrics)
    # end

    # update :cleanup_old_records do
    #   description("Cleanup old usage records")
    #   change(Lang.Accounts.APIUsage.Changes.CleanupOldRecords)
    # end

    read :unprocessed_metrics do
      description("Read unprocessed metrics for background processing")
      filter(expr(processed == false))
      prepare(build(limit: 1000, sort: [inserted_at: :asc]))
    end

    read :usage_for_user do
      argument(:user_id, :uuid, allow_nil?: false)
      argument(:month_year, :string)
      filter(expr(user_id == ^arg(:user_id)))
      filter(expr(if is_nil(^arg(:month_year)), do: true, else: month_year == ^arg(:month_year)))
    end

    read :monthly_stats do
      argument(:user_id, :uuid, allow_nil?: false)
      argument(:month_year, :string, allow_nil?: false)

      filter(expr(user_id == ^arg(:user_id) and month_year == ^arg(:month_year)))

      prepare(fn query, _context ->
        query
        |> Ash.Query.aggregate(:total_requests, :count)
        |> Ash.Query.aggregate(:successful_requests, :count, filter: expr(status == :success))
        |> Ash.Query.aggregate(:error_requests, :count, filter: expr(status == :error))
        |> Ash.Query.aggregate(:rate_limited_requests, :count,
          filter: expr(status == :rate_limited)
        )
        |> Ash.Query.aggregate(:total_content_size, :sum, field: :content_size_bytes)
        |> Ash.Query.aggregate(:avg_processing_time, :avg, field: :processing_time_ms)
        |> Ash.Query.limit(1)
      end)
    end

    read :operation_breakdown do
      argument(:user_id, :uuid, allow_nil?: false)
      argument(:month_year, :string, allow_nil?: false)

      filter(expr(user_id == ^arg(:user_id) and month_year == ^arg(:month_year)))

      prepare(fn query, _context ->
        query
        |> Ash.Query.group(:operation_type)
        |> Ash.Query.aggregate(:count, :count)
        |> Ash.Query.aggregate(:avg_processing_time, :avg, field: :processing_time_ms)
      end)
    end

    read :format_breakdown do
      argument(:user_id, :uuid, allow_nil?: false)
      argument(:month_year, :string, allow_nil?: false)

      filter(
        expr(user_id == ^arg(:user_id) and month_year == ^arg(:month_year) and not is_nil(format))
      )

      prepare(fn query, _context ->
        query
        |> Ash.Query.group(:format)
        |> Ash.Query.aggregate(:count, :count)
        |> Ash.Query.aggregate(:total_size, :sum, field: :content_size_bytes)
      end)
    end

    read :recent_usage do
      argument(:user_id, :uuid, allow_nil?: false)
      argument(:limit, :integer, default: 100)

      filter(expr(user_id == ^arg(:user_id)))
      prepare(build(sort: [inserted_at: :desc], limit: arg(:limit)))
    end

    destroy :cleanup_old_usage do
      # Clean up usage records older than 13 months
      filter(expr(inserted_at < ago(13, :month)))
    end
  end

  relationships do
    belongs_to :user, Lang.Accounts.User do
      source_attribute(:user_id)
      destination_attribute(:id)
    end
  end

  validations do
    validate(present([:user_id, :operation_type, :status, :month_year]))

    validate one_of(:operation_type, [:analyze, :conversation, :stylometrics, :timemachine, :lsp]) do
      message("must be a valid operation type")
    end

    validate one_of(:status, [:success, :error, :rate_limited]) do
      message("must be a valid status")
    end

    validate compare(:content_size_bytes, greater_than_or_equal_to: 0) do
      where([present(:content_size_bytes)])
      message("content size cannot be negative")
    end

    validate compare(:processing_time_ms, greater_than_or_equal_to: 0) do
      where([present(:processing_time_ms)])
      message("processing time cannot be negative")
    end
  end

  preparations do
    prepare(build(sort: [inserted_at: :desc]))
  end

  # TODO: Re-enable after fixing define_for syntax
  # code_interface do
  #   define_for(Lang.Accounts)
  #   define(:log_usage)
  #   define(:usage_for_user)
  #   define(:monthly_stats)
  #   define(:operation_breakdown)
  #   define(:format_breakdown)
  #   define(:recent_usage)
  #   define(:cleanup_old_usage, action: :destroy)
  #   define(:read_all, action: :read)
  # end

  # Convenience functions for common queries
  def current_month_usage(user_id) do
    now = DateTime.utc_now()
    month_year = "#{now.year}-#{String.pad_leading(to_string(now.month), 2, "0")}"

    __MODULE__
    |> Ash.Query.for_read(:usage_for_user)
    |> Ash.Query.set_arguments(%{user_id: user_id, month_year: month_year})
    |> Ash.read()
  end

  def current_month_count(user_id) do
    case current_month_usage(user_id) do
      {:ok, usage_records} -> {:ok, length(usage_records)}
      error -> error
    end
  end

  # Helper function to directly query usage for user
  def usage_for_user(args) do
    __MODULE__
    |> Ash.Query.for_read(:usage_for_user)
    |> Ash.Query.set_arguments(args)
    |> Ash.read()
  end

  def is_over_limit?(user, operation_count \\ 1) do
    case current_month_count(user.id) do
      {:ok, current_count} ->
        current_count + operation_count > user.monthly_request_limit

      {:error, _} ->
        # Default to allowing if we can't check
        false
    end
  end

  def usage_percentage(user) do
    case current_month_count(user.id) do
      {:ok, current_count} ->
        percentage = current_count / user.monthly_request_limit * 100
        {:ok, min(percentage, 100.0)}

      error ->
        error
    end
  end
end
