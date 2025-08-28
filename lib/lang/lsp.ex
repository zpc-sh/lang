defmodule Lang.LSP do
  @moduledoc """
  Domain for Language Server Protocol resources and operations.

  This domain manages LSP-related resources including:
  - LSP method definitions
  - Protocol handlers
  - Server state management
  """

  use Ash.Domain

  resources do
    resource(Lang.LSP.LspMethod)
  end
end
