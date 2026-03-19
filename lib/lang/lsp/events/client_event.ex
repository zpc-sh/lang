defmodule Lang.LSP.Events.ClientEvent do
  use Ash.Resource,
    otp_app: :lang,
    domain: Lang.LSP,
    data_layer: Ash.DataLayer.Ets,
    notifiers: [Ash.Notifier.PubSub]

  # Publish client lifecycle/activity events via Ash PubSub
  pub_sub do
    # Final topic will be "lsp:clients:global"
    prefix("lsp:clients")
    module(LangWeb.Endpoint)
    publish(:emit, "global")

    # Trim event payload for broadcast
    transform(fn evt ->
      %{
        type: evt.event_type,
        payload: evt.payload,
        at: evt.at
      }
    end)
  end

  attributes do
    uuid_primary_key(:id)

    attribute :event_type, :atom do
      allow_nil?(false)
      constraints(one_of: [:connected, :initialized, :activity, :disconnected])
    end

    attribute :payload, :map do
      allow_nil?(false)
      default(%{})
    end

    attribute :at, :utc_datetime_usec do
      allow_nil?(false)
      default(&DateTime.utc_now/0)
    end
  end

  actions do
    defaults([:read])

    create :emit do
      accept([:event_type, :payload, :at])
      primary?(true)
    end
  end
end
