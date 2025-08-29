defmodule Lang.Generate do
  @moduledoc """
  Ash domain for Generative AI requests and artifacts.
  """

  use Ash.Domain

  resources do
    resource(Lang.Generate.Request)
    resource(Lang.Generate.Artifact)
  end
end
