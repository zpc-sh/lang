defmodule Lang.LspDomain do
  @moduledoc """
  The domain for LSP-related resources and operations.
  """
  use Ash.Domain

  resources do
    resource Lang.LspMeasurementEvent
    # Add other LSP-related resources here as needed.
  end
end