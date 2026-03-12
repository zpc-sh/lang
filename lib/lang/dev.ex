defmodule Lang.Dev do
  @moduledoc """
  Dev-only Ash domain for ModelRegistry and related tools.
  """
  use Ash.Domain

  resources do
    resource Lang.Dev.ModelRegistry
    resource Lang.Dev.ModelState
    resource Lang.Dev.ModelEvent
    resource Lang.Dev.LSPTap
    resource Lang.Dev.LSPTrace
  end
end

