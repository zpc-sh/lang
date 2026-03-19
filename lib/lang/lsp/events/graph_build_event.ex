defmodule Lang.LSP.Events.GraphBuildEvent do
  use Ash.Resource,
    otp_app: :lang,
    domain: Lang.LSP,
    data_layer: Ash.DataLayer.Ets,
    notifiers: [Ash.Notifier.PubSub]

  @moduledoc """
  Streaming events for Knowledge Graph build progress, published via Ash PubSub.

  Topic: lsp:kg_build:<stream_id>
  """

  pub_sub do
    prefix("lsp:kg_build")
    module(LangWeb.Endpoint)
    publish(:emit, [:stream_id])

    transform(fn evt ->
      %{
        stream_id: evt.stream_id,
        phase: evt.phase,
        index: evt.index,
        total: evt.total,
        progress: evt.progress,
        complete: evt.complete,
        payload: evt.payload
      }
    end)
  end

  attributes do
    uuid_primary_key(:id)
    attribute :stream_id, :string, allow_nil?: false
    attribute :phase, :atom, allow_nil?: false, default: :start
    attribute :index, :integer, allow_nil?: true
    attribute :total, :integer, allow_nil?: true
    attribute :progress, :float, allow_nil?: true
    attribute :complete, :boolean, allow_nil?: false, default: false
    attribute :payload, :map, allow_nil?: true, default: %{}
  end

  actions do
    defaults([:read])

    create :emit do
      accept([:stream_id, :phase, :index, :total, :progress, :complete, :payload])
      primary?(true)
    end
  end
end

