defmodule Lang.LSP.Events.DiagnosticEvent do
  use Ash.Resource,
    otp_app: :lang,
    domain: Lang.LSP,
    data_layer: Ash.DataLayer.Ets,
    notifiers: [Ash.Notifier.PubSub]

  pub_sub do
    # Topic: lsp:diagnostics:global
    prefix("lsp:diagnostics")
    module(LangWeb.Endpoint)
    publish(:emit, "global")

    transform(fn evt ->
      %{
        uri: evt.uri,
        diagnostics: evt.diagnostics,
        at: evt.at
      }
    end)
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:uri, :string, allow_nil?: false)
    attribute(:diagnostics, :map, allow_nil?: false, default: %{})
    attribute(:at, :utc_datetime_usec, allow_nil?: false, default: &DateTime.utc_now/0)
  end

  actions do
    defaults([:read])

    create :emit do
      accept([:uri, :diagnostics, :at])
      primary?(true)
    end
  end
end
