defmodule Lang.Workspaces do
  @moduledoc """
  Ash domain for Workspace resources.
  """

  use Ash.Domain

  resources do
    resource(Lang.Workspace.Symbol)
    resource(Lang.Workspace.Reference)
    resource(Lang.Workspace.Fragment)
    resource(Lang.Workspace.Pattern)
    resource(Lang.Workspace.ChatMessage)
    resource(Lang.Workspace.WorkingSet)
    resource(Lang.Workspace.Workspace)
    resource(Lang.Workspace.WorkingSetSymbol)
  end
end
