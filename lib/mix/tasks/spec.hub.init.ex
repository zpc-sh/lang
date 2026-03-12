defmodule Mix.Tasks.Spec.Hub.Init do
  use Mix.Task
  @shortdoc "Initialize a spec-hub directory with standard layout and docs"
  @moduledoc """
  Usage:
    mix spec.hub.init --dest ../lang-spec-hub

  Creates:
  - <hub>/requests/
  - <hub>/schemas/ (copies ack/message/request schema)
  - <hub>/docs/ (copies AGENTS.codex.md and receiver guide)
  - <hub>/index.md (empty scaffold)
  """

  @impl true
  def run(argv) do
    {opts, _, _} = OptionParser.parse(argv, switches: [dest: :string])
    hub = Keyword.get(opts, :dest) || Mix.raise("Provide --dest <hub_dir>")

    File.mkdir_p!(hub)
    req_dir = Path.join(hub, "requests")
    sch_dir = Path.join(hub, "schemas")
    docs_dir = Path.join(hub, "docs")
    File.mkdir_p!(req_dir)
    File.mkdir_p!(sch_dir)
    File.mkdir_p!(docs_dir)

    # Copy schemas
    copy!(Path.join([File.cwd!(), "work/spec_requests/ack.schema.json"]), Path.join(sch_dir, "ack.schema.json"))
    copy!(Path.join([File.cwd!(), "work/spec_requests/message.schema.json"]), Path.join(sch_dir, "message.schema.json"))
    copy!(Path.join([File.cwd!(), "work/spec_requests/schema.json"]), Path.join(sch_dir, "request.schema.json"))

    # Copy docs
    copy!(Path.join([File.cwd!(), "AGENTS.codex.md"]), Path.join(docs_dir, "AGENTS.codex.md"))
    copy!(Path.join([File.cwd!(), "work/spec_requests/README.receivers.md"]), Path.join(docs_dir, "README.receivers.md"))

    index = Path.join(hub, "index.md")
    if !File.exists?(index), do: File.write!(index, "# Spec Hub Index\n\nRun `mix spec.index --hub #{hub}` to generate contents.\n")

    Mix.shell().info("Initialized spec-hub at #{hub}")
  end

  defp copy!(src, dst) do
    File.cp!(src, dst)
  end
end
