defmodule Mix.Tasks.Spec.Receiver.Init do
  use Mix.Task
  @shortdoc "Bootstrap receiver-side handoff files into a destination folder"
  @moduledoc """
  Usage:
    mix spec.receiver.init [--dest /path/to/other/repo/work/spec_requests]

  Copies the receiver guide and ack templates into the destination directory.
  If --dest is omitted, uses SPEC_HANDOFF_DIR env var.
  """

  @impl true
  def run(argv) do
    {opts, _, _} = OptionParser.parse(argv, switches: [dest: :string])
    dest = Keyword.get(opts, :dest) || System.get_env("SPEC_HANDOFF_DIR") ||
             Mix.raise("Provide --dest or set SPEC_HANDOFF_DIR")

    src_root = Path.join([File.cwd!(), "work", "spec_requests"])
    files = [
      {"README.receivers.md", Path.join(src_root, "README.receivers.md")},
      {"ack.schema.json", Path.join(src_root, "ack.schema.json")},
      {"ack.example.json", Path.join(src_root, "ack.example.json")}
    ]

    File.mkdir_p!(dest)

    Enum.each(files, fn {name, src} ->
      target = Path.join(dest, name)
      File.cp!(src, target)
      Mix.shell().info("Copied #{name} -> #{dest}")
    end)
  end
end
