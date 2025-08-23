defmodule Lang.MCP.Resources.Connection do
  @moduledoc """
  Ash resource for tracking active MCP connections.

  This resource manages the state of active MCP connections, including
  their lifecycle, health status, usage statistics, and relationships
  to server configurations and users.
  """

  use Ash.Resource,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJsonApi.Resource],
    domain: nil

  postgres do
    table("mcp_connections")
    repo(Lang.Repo)
  end

  json_api do
    type("mcp_connection")
    includes([:server_config, :user, :session])

    routes do
      base("/api/v2/mcp/connections")
      get(:read)
      index(:read)
      post(:create)
      patch(:update)
      delete(:destroy)
    end
  end

  attributes do
    uuid_primary_key(:id)

    attribute :connection_id, :string do
      allow_nil?(false)
      description("Unique identifier for the MCP connection")
    end

    attribute :stream_id, :string do
      allow_nil?(true)
      description("Associated stream ID for WebSocket communication")
    end

    attribute :status, :atom do
      allow_nil?(false)
      default(:pending)

      constraints(
        one_of: [:pending, :connecting, :connected, :disconnecting, :disconnected, :error]
      )

      description("Current status of the MCP connection")
    end

    attribute :pid, :string do
      allow_nil?(true)
      description("Process ID of the MCP server process (for monitoring)")
    end

    attribute :host_info, :map do
      default(%{})
      description("Information about the host running the MCP server")
    end

    attribute :connection_params, :map do
      default(%{})
      description("Parameters used to establish the connection")
    end

    attribute :health_status, :atom do
      allow_nil?(false)
      default(:unknown)
      constraints(one_of: [:healthy, :unhealthy, :unknown, :checking])
      description("Health status of the connection")
    end

    attribute :last_health_check, :utc_datetime do
      description("Timestamp of the last health check")
    end

    attribute :last_activity, :utc_datetime do
      allow_nil?(false)
      default(&DateTime.utc_now/0)
      description("Timestamp of the last activity on this connection")
    end

    attribute :request_count, :integer do
      allow_nil?(false)
      default(0)
      description("Total number of requests processed by this connection")
    end

    attribute :error_count, :integer do
      allow_nil?(false)
      default(0)
      description("Total number of errors encountered")
    end

    attribute :bytes_transferred, :integer do
      allow_nil?(false)
      default(0)
      description("Total bytes transferred through this connection")
    end

    attribute :connection_metadata, :map do
      default(%{})
      description("Additional connection metadata and JSON-LD context")
    end

    attribute :circuit_breaker_state, :atom do
      allow_nil?(false)
      default(:closed)
      constraints(one_of: [:closed, :open, :half_open])
      description("Circuit breaker state for this connection")
    end

    attribute :failure_count, :integer do
      allow_nil?(false)
      default(0)
      description("Number of consecutive failures")
    end

    attribute :expires_at, :utc_datetime do
      description("When this connection should be automatically cleaned up")
    end

    timestamps()
  end

  relationships do
    belongs_to :server_config, Lang.MCP.Resources.ServerConfig do
      description("MCP server configuration used for this connection")
      allow_nil?(false)
      public?(true)
    end

    belongs_to :user, Lang.Accounts.User do
      description("User who owns this connection")
      allow_nil?(false)
      public?(true)
    end

    belongs_to :session, Lang.MCP.Resources.Session do
      description("Session this connection belongs to")
      allow_nil?(true)
      public?(true)
    end

    has_many :requests, Lang.MCP.Resources.Request do
      description("Requests made through this connection")
      public?(true)
    end
  end

  actions do
    defaults([:read])

    create :create do
      accept([
        :connection_id,
        :stream_id,
        :status,
        :pid,
        :host_info,
        :connection_params,
        :health_status,
        :connection_metadata,
        :expires_at,
        :server_config_id,
        :user_id,
        :session_id
      ])

      # connection_metadata initialization can be added via a change module later
      change(set_attribute(:last_activity, &DateTime.utc_now/0))

      after_action(fn changeset, result ->
        Task.start(fn ->
          Lang.Billing.MCPConnectionTracker.track_connection(
            result.user_id,
            result.connection_id,
            result.server_config.server_type,
            %{
              session_id: result.session_id,
              config_id: result.server_config_id
            }
          )
        end)

        {:ok, result}
      end)
    end

    update :update do
      accept([
        :stream_id,
        :status,
        :pid,
        :host_info,
        :health_status,
        :last_health_check,
        :last_activity,
        :request_count,
        :error_count,
        :bytes_transferred,
        :connection_metadata,
        :circuit_breaker_state,
        :failure_count,
        :expires_at
      ])

      # connection_metadata updates can be added via a change module later
    end

    update :mark_connected do
      accept([])
      change(set_attribute(:status, :connected))
      change(set_attribute(:last_activity, &DateTime.utc_now/0))
    end

    update :mark_disconnected do
      accept([])
      change(set_attribute(:status, :disconnected))
    end

    update :mark_error do
      argument(:error_details, :map, allow_nil?: false)

      change(set_attribute(:status, :error))
      change(increment(:error_count))
      change(increment(:failure_count))
      # enrich connection_metadata with error details via a change module later
    end

    update :record_activity do
      accept([:bytes_transferred])
      change(set_attribute(:last_activity, &DateTime.utc_now/0))
      change(increment(:request_count))
    end

    update :update_health do
      argument(:health_status, :atom, allow_nil?: false)

      change(set_attribute(:health_status, arg(:health_status)))
      change(set_attribute(:last_health_check, &DateTime.utc_now/0))
    end

    update :update_circuit_breaker do
      argument(:state, :atom, allow_nil?: false)

      change(set_attribute(:circuit_breaker_state, arg(:state)))
    end

    destroy :destroy do
    end

    read :by_connection_id do
      argument(:connection_id, :string, allow_nil?: false)
      filter(expr(connection_id == ^arg(:connection_id)))
    end

    read :by_user do
      argument(:user_id, :uuid, allow_nil?: false)
      filter(expr(user_id == ^arg(:user_id)))
    end

    read :by_session do
      argument(:session_id, :uuid, allow_nil?: false)
      filter(expr(session_id == ^arg(:session_id)))
    end

    read :by_status do
      argument(:status, :atom, allow_nil?: false)
      filter(expr(status == ^arg(:status)))
    end

    read :active_connections do
      filter(expr(status in [:connecting, :connected]))
    end

    read :unhealthy_connections do
      filter(expr(health_status == :unhealthy or circuit_breaker_state == :open))
    end

    read :expired_connections do
      filter(expr(expires_at < ^DateTime.utc_now()))
    end

    # Defer advanced idle filtering until finalized
  end

  # Policies will be added after the MCP domain and authorizers are finalized

  validations do
    validate present([:connection_id, :server_config_id, :user_id]) do
      message("Connection ID, server config, and user are required")
    end

    validate match(:connection_id, ~r/^mcp_conn_[a-f0-9]+$/) do
      message("Connection ID must follow the format mcp_conn_[hex]")
    end

    validate compare(:request_count, greater_than_or_equal_to: 0) do
      message("Request count cannot be negative")
    end

    validate compare(:error_count, greater_than_or_equal_to: 0) do
      message("Error count cannot be negative")
    end

    validate compare(:failure_count, greater_than_or_equal_to: 0) do
      message("Failure count cannot be negative")
    end
  end

  # Resource-level changes/preparations can be added once MCP domain is finalized

  # JSON-LD metadata builders

  defp build_json_ld_metadata(_changeset) do
    %{
      "@context" => "https://lang.nocsi.com/schema/v1/mcp-connection",
      "@type" => "MCPConnection",
      "version" => "1.0.0",
      "created_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "schema_version" => "v1",
      "lifecycle_events" => []
    }
  end

  defp update_json_ld_metadata(changeset) do
    existing_metadata = Ash.Changeset.get_attribute(changeset, :metadata) || %{}

    event = %{
      "event" => "connection_updated",
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "changes" => Ash.Changeset.changes(changeset) |> Map.keys()
    }

    events =
      [event | Map.get(existing_metadata, "lifecycle_events", [])]
      # Keep only last 10 events
      |> Enum.take(10)

    Map.merge(existing_metadata, %{
      "updated_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "lifecycle_events" => events
    })
  end

  defp add_error_metadata(changeset, error_details) do
    existing_metadata = Ash.Changeset.get_attribute(changeset, :metadata) || %{}

    error_event = %{
      "event" => "connection_error",
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "error_details" => error_details
    }

    events =
      [error_event | Map.get(existing_metadata, "lifecycle_events", [])]
      |> Enum.take(10)

    Map.merge(existing_metadata, %{
      "last_error" => error_details,
      "last_error_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "lifecycle_events" => events
    })
  end

  # Helper functions omitted for initial version
end
