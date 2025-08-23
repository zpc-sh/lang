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
end
