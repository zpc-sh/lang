defmodule Lang.Dev do
  @moduledoc """
  Dev-only Ash domain for ModelRegistry and related tools.
  """
  use Ash.Domain

  resources do
    resource Lang.Dev.ModelRegistry
  end
end
