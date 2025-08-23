defmodule Lang.Events do
  @moduledoc """
  LANG Events Domain

  This domain handles all event-driven functionality using proper Ash resources
  with PubSub notifications for real-time updates.
  """

  use Ash.Domain

  resources do
    resource(Lang.Events.ApiUsageEvent)
    resource(Lang.Events.UserActivityEvent)
  end

  @doc """
  Tracks an event using Ash resources. Creates the appropriate event record
  and broadcasts it via PubSub for real-time updates.

  ## Examples

      Events.track_event(%{
        event_type: "user_login_success",
        user_id: user.id,
        metadata: %{email: user.email}
      })

      Events.track_event(%{
        event_type: "api_call_made",
        user_id: user.id,
        organization_id: org.id,
        metadata: %{endpoint: "/api/v1/analyze", status: 200}
      })
  """
  def track_event(attrs) do
    case determine_event_resource(attrs) do
      {:user_activity, resource} ->
        create_user_activity_event(resource, attrs)

      {:api_usage, resource} ->
        create_api_usage_event(resource, attrs)

      {:error, reason} ->
        require Logger
        Logger.warning("Failed to track event: #{inspect(reason)}, attrs: #{inspect(attrs)}")
        {:error, reason}
    end
  end

  # Private functions

  defp determine_event_resource(attrs) do
    case Map.get(attrs, :event_type) do
      event_type
      when event_type in [
             "user_login_success",
             "user_login_failed",
             "user_registered",
             "user_logged_out",
             "password_reset_requested",
             "password_reset_completed",
             "api_key_created",
             "api_key_revoked"
           ] ->
        {:user_activity, Lang.Events.UserActivityEvent}

      event_type
      when event_type in [
             "api_call_made",
             "api_call_failed",
             "rate_limit_exceeded",
             "usage_limit_exceeded",
             "billing_event"
           ] ->
        {:api_usage, Lang.Events.ApiUsageEvent}

      nil ->
        {:error, :missing_event_type}

      unknown_type ->
        # Default to user activity for unknown types
        require Logger
        Logger.info("Unknown event type '#{unknown_type}', defaulting to UserActivityEvent")
        {:user_activity, Lang.Events.UserActivityEvent}
    end
  end

  defp create_user_activity_event(resource, attrs) do
    event_attrs = %{
      event_type: Map.get(attrs, :event_type),
      user_id: Map.get(attrs, :user_id),
      metadata: Map.get(attrs, :metadata, %{}),
      occurred_at: DateTime.utc_now()
    }

    case resource.create(event_attrs) do
      {:ok, event} ->
        # Broadcast via PubSub
        Phoenix.PubSub.broadcast(
          Lang.PubSub,
          "user_activity:#{event.user_id}",
          {:user_activity_event, event}
        )

        Phoenix.PubSub.broadcast(
          Lang.PubSub,
          "events:all",
          {:event_tracked, event}
        )

        {:ok, event}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp create_api_usage_event(resource, attrs) do
    event_attrs = %{
      event_type: Map.get(attrs, :event_type),
      user_id: Map.get(attrs, :user_id),
      organization_id: Map.get(attrs, :organization_id),
      metadata: Map.get(attrs, :metadata, %{}),
      occurred_at: DateTime.utc_now()
    }

    case resource.create(event_attrs) do
      {:ok, event} ->
        # Broadcast via PubSub
        if event.user_id do
          Phoenix.PubSub.broadcast(
            Lang.PubSub,
            "api_usage:#{event.user_id}",
            {:api_usage_event, event}
          )
        end

        if event.organization_id do
          Phoenix.PubSub.broadcast(
            Lang.PubSub,
            "org_usage:#{event.organization_id}",
            {:api_usage_event, event}
          )
        end

        Phoenix.PubSub.broadcast(
          Lang.PubSub,
          "events:all",
          {:event_tracked, event}
        )

        {:ok, event}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Gets recent events for a user using Ash queries.
  """
  def get_user_events(user_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    import Ash.Query

    Lang.Events.UserActivityEvent
    |> Ash.Query.filter(user_id == ^user_id)
    |> Ash.Query.sort(occurred_at: :desc)
    |> Ash.Query.limit(limit)
    |> Ash.read()
  end

  @doc """
  Gets API usage events for an organization using Ash queries.
  """
  def get_organization_usage(organization_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)

    import Ash.Query

    Lang.Events.ApiUsageEvent
    |> Ash.Query.filter(organization_id == ^organization_id)
    |> Ash.Query.sort(occurred_at: :desc)
    |> Ash.Query.limit(limit)
    |> Ash.read()
  end
end
