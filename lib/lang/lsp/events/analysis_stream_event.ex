defmodule Lang.LSP.Events.AnalysisStreamEvent do
  use Ash.Resource,
    otp_app: :lang,
    domain: Lang.LSP,
    data_layer: Ash.DataLayer.Ets,
    notifiers: [Ash.Notifier.PubSub]

  pub_sub do
    # Topic: lsp:analysis_stream:<stream_id>
    prefix("lsp:analysis_stream")
    module(LangWeb.Endpoint)
    publish(:emit, [:stream_id])

    transform(fn evt ->
      %{
        stream_id: evt.stream_id,
        chunk: evt.chunk,
        index: evt.index,
        complete: evt.complete,
        uri: evt.uri
      }
    end)
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:stream_id, :string, allow_nil?: false)
    attribute(:chunk, :map, allow_nil?: true)
    attribute(:index, :integer, allow_nil?: true)
    attribute(:complete, :boolean, allow_nil?: false, default: false)
    attribute(:uri, :string, allow_nil?: true)
  end

  actions do
    defaults([:read])

    create :emit do
      accept([:stream_id, :chunk, :index, :complete, :uri])
      primary?(true)
    end
  end
end
