defmodule Mix.Tasks.Spec.Autosync do
  use Mix.Task
  @shortdoc "Convenience wrapper around spec.sync with SPEC_HANDOFF_DIR"
  @moduledoc """
  Usage:
    mix spec.autosync --id <req>

  Resolves peer as SPEC_HANDOFF_DIR/<id>
  """

  @impl true
  def run(argv) do
    {opts, _, _} = OptionParser.parse(argv, switches: [id: :string, api: :string, token: :string, workspace: :string])
    id = Keyword.get(opts, :id) || Mix.raise("Missing --id")
    base = System.get_env("SPEC_HANDOFF_DIR") || Mix.raise("Set SPEC_HANDOFF_DIR or pass --peer to spec.sync")
    peer = Path.join(base, id)
    extra = case Keyword.get(opts, :api) do
      nil -> []
      api ->
        token = Keyword.get(opts, :token)
        workspace = Keyword.get(opts, :workspace)
        ["--api", api]
        ++ (token && ["--token", token] || [])
        ++ (workspace && ["--workspace", workspace] || [])
    end
    Mix.Task.run("spec.sync", ["--id", id, "--peer", peer] ++ extra)
  end
end
