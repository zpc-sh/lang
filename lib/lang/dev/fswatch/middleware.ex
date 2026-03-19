defmodule Lang.Dev.FSWatch.Middleware do
  @moduledoc """
  Behaviour for FS watch log middleware.

  Each middleware receives the event and an options map and returns one of:
  - {:ok, event, opts} to continue the pipeline
  - {:emit, iodata()} to short-circuit and produce output
  - :skip to drop the event
  """

  @callback handle(%{name: atom(), kind: atom(), path: String.t(), topic: String.t()}, map()) ::
              {:ok, map(), map()} | {:emit, iodata()} | :skip
end

