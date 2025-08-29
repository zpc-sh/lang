defmodule Lang.Analysis.StreamListener do
  @moduledoc """
  Helper to subscribe to analysis stream PubSub updates produced by
  `Lang.LSP.Dispatch` analyze_stream wiring.
  """

  @topic_prefix "lsp:analysis:"

  def subscribe(stream_id) do
    Phoenix.PubSub.subscribe(Lang.PubSub, @topic_prefix <> to_string(stream_id))
  end
end

