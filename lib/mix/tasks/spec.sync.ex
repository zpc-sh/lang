defmodule Mix.Tasks.Spec.Sync do
  use Mix.Task
  @shortdoc "Pull from peer then push local outbox (one-shot sync)"
  @moduledoc """
  Usage:
    mix spec.sync --id <request_id> --peer /path/to/peer/work/spec_requests/<id>

  Equivalent to:
    mix spec.msg.pull --id <id> --from <peer>/outbox
    mix spec.msg.push --id <id> --dest <peer>/inbox
  """

  @impl true
  def run(argv) do
    {opts, _, _} = OptionParser.parse(argv, switches: [id: :string, peer: :string, api: :string, token: :string, workspace: :string])
    id = Keyword.get(opts, :id) || Mix.raise("Missing --id")
    peer = Keyword.get(opts, :peer) || Mix.raise("Missing --peer")

    extra = case Keyword.get(opts, :api) do
      nil -> []
      api ->
        token = Keyword.get(opts, :token)
        workspace = Keyword.get(opts, :workspace)
        ["--api", api]
        ++ (token && ["--token", token] || [])
        ++ (workspace && ["--workspace", workspace] || [])
    end

    Mix.Task.run("spec.msg.pull", ["--id", id, "--from", Path.join(peer, "outbox")] ++ extra)
    Mix.Task.run("spec.msg.push", ["--id", id, "--dest", Path.join(peer, "inbox")] ++ extra)
    Mix.Task.run("spec.thread.render", ["--id", id])
  end
end
