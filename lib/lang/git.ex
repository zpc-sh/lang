defmodule Lang.Git do
  @moduledoc """
  Ash Domain for Git resources.
  """

  use Ash.Domain

  resources do
    resource(Lang.Git.Repo)
    resource(Lang.Git.RepoSnapshot)
    resource(Lang.Git.Artifact)
  end
end
