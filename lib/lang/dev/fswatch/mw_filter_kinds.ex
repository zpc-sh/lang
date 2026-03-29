defmodule Lang.Dev.FSWatch.MW.FilterKinds do
  @moduledoc """
  Drops events that are not in the allowed kinds list.

  Options:
  - :kinds -> list of atoms, e.g., [:created, :modified]
    If nil or empty, all kinds are allowed.
  """

  @behaviour Lang.Dev.FSWatch.Middleware

  @impl true
  def handle(%{kind: kind} = event, opts) do
    kinds = Map.get(opts, :kinds)
    allow? = Lang.Dev.FSWatch.Util.allow_kind?(kind, kinds)
    if allow?, do: {:ok, event, opts}, else: :skip
  end
end

