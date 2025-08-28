defmodule Lang.Workspaces do
  @moduledoc """
  Ash domain for Workspace resources.
  """

  use Ash.Domain

  if Code.ensure_loaded?(Lang.Workspace.Workspace) do
    resources do
      resource(Lang.Workspace.Workspace)
    end
  end
end
