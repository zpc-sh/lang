defmodule Mix.Tasks.Spec.Export.Docs do
  use Mix.Task
  @shortdoc "Copy handoff docs into another repo (agent protocol and receiver guide)"
  @moduledoc """
  Usage:
    mix spec.export.docs --dest /path/to/other/repo

  Copies:
  - AGENTS.codex.md
  - work/spec_requests/README.receivers.md
  - work/spec_requests/*.schema.json (ack/message)
  - work/spec_requests/ack.example.json
  """

  @impl true
  def run(argv) do
    {opts, _, _} = OptionParser.parse(argv, switches: [dest: :string])
    dest = Keyword.get(opts, :dest) || Mix.raise("Provide --dest")

    # Copy AGENTS.codex.md
    copy!("AGENTS.codex.md", Path.join(dest, "AGENTS.codex.md"))

    # Copy receiver docs & schemas
    src_spec = Path.join([File.cwd!(), "work", "spec_requests"])
    File.mkdir_p!(Path.join(dest, "work/spec_requests"))
    for name <- [
      "README.receivers.md",
      "ack.schema.json",
      "ack.example.json",
      "message.schema.json"
    ] do
      copy!(Path.join(src_spec, name), Path.join(dest, "work/spec_requests/" <> name))
    end

    # Copy JSON-LD context into hub schemas/contexts
    ctx_src = Path.join(src_spec, "contexts/spec.jsonld")
    ctx_dst = Path.join(dest, "schemas/contexts/spec.jsonld")
    File.mkdir_p!(Path.dirname(ctx_dst))
    copy!(ctx_src, ctx_dst)

    Mix.shell().info("Exported handoff docs to #{dest}")
  end

  defp copy!(src, dst) do
    File.mkdir_p!(Path.dirname(dst))
    File.cp!(src, dst)
  end
end
