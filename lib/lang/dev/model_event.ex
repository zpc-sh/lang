defmodule Lang.Dev.ModelEvent do
  @moduledoc """
  Dev model pipeline events, emitted via Ash.Notifier.PubSub (AshEvents‑style).

  Topic prefix: "dev:models". Subscriptions receive PubSub messages on create events.
  """

  use Ash.Resource,
    domain: Lang.Dev,
    data_layer: Ash.DataLayer.Ets,
    notifiers: [Ash.Notifier.PubSub]

  ets do
    private?(false)
  end

  pub_sub do
    # Broadcasts on: "dev:models:global" for log creates
    prefix("dev:models")
    module(LangWeb.Endpoint)
    publish(:log, "global")
  end

  attributes do
    uuid_primary_key :id
    attribute :event_type, :string, allow_nil?: false
    attribute :model_id, :string, allow_nil?: false
    attribute :status, :string, allow_nil?: true
    attribute :path, :string, allow_nil?: true
    attribute :job_id, :string, allow_nil?: true
    attribute :reason, :string, allow_nil?: true
    attribute :metadata, :map, allow_nil?: true, default: %{}
    attribute :at, :utc_datetime_usec, allow_nil?: false, default: &DateTime.utc_now/0
  end

  actions do
    defaults [:read]

    create :log do
      primary? true
      accept [:event_type, :model_id, :status, :path, :job_id, :reason, :metadata, :at]
    end
  end
end

