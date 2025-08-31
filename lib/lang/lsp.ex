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
    resource(Lang.LSP.Events.CompletionEvent)
    resource(Lang.LSP.Events.ClientEvent)
    resource(Lang.LSP.Events.MetricEvent)
    resource(Lang.LSP.Events.DiagnosticEvent)
    resource(Lang.LSP.Events.AnalysisStreamEvent)
  end
end
