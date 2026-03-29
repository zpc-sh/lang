defmodule Lang.Think do
  @moduledoc """
  Ash domain for Cognitive Intelligence requests and results.
  """

  use Ash.Domain

  resources do
    resource(Lang.Think.Request)
    resource(Lang.Think.Result)
  end
end
