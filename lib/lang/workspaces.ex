defmodule Lang.Workspaces do
  @moduledoc """
  Ash domain for Workspace resources.
  """

  use Ash.Domain

  resources do
    resource(Lang.Workspace.Workspace)
  end
end
