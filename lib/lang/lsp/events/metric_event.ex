defmodule Lang.LSP.Events.MetricEvent do
  use Ash.Resource,
    otp_app: :lang,
    domain: Lang.LSP,
    data_layer: Ash.DataLayer.Ets,
    notifiers: [Ash.Notifier.PubSub]

  # Publish LSP metrics via Ash PubSub
  pub_sub do
    # Final topic will be "lsp:metrics:global"
    prefix("lsp:metrics")
    module(LangWeb.Endpoint)
    publish(:emit, "global")

    transform(fn evt ->
      %{
        event: evt.event,
        measurements: evt.measurements,
        metadata: evt.metadata,
        at: evt.at
      }
    end)
  end

  attributes do
    uuid_primary_key(:id)

    attribute :event, :atom do
      allow_nil?(false)
      constraints(one_of: [:request, :response, :connection])
    end

    attribute :measurements, :map do
      allow_nil?(false)
      default(%{})
    end

    attribute :metadata, :map do
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
      accept([:event, :measurements, :metadata, :at])
      primary?(true)
    end
  end
end
