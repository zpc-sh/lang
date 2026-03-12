defmodule Mix.Tasks.Spec.Say do
  use Mix.Task
  @shortdoc "Create a message, push to peer, and render the thread"
  @moduledoc """
  Usage:
    mix spec.say --id <req> --type comment|question|proposal|decision --body body.md \
                 [--attach file ...] [--ref-path request.json] [--ref-pointer /ptr] \
                 [--dest /peer/path/work/spec_requests/<id>/inbox]

  If --dest omitted, uses SPEC_HANDOFF_DIR/<id>/inbox
  """

  @impl true
  def run(argv) do
    {opts, _, _} = OptionParser.parse(argv,
      switches: [id: :string, type: :string, body: :string, ref_path: :string, ref_pointer: :string, dest: :string, attach: :keep]
    )
    id = req!(opts, :id)
    type = req!(opts, :type)
    body = req!(opts, :body)
    dest = Keyword.get(opts, :dest)
    ref_args = ref_opts(opts)
    attach_args = Enum.flat_map(Keyword.get_values(opts, :attach), fn f -> ["--attach", f] end)

    Mix.Task.run("spec.msg.new", ["--id", id, "--type", type, "--body", body] ++ ref_args ++ attach_args)

    dest_inbox = dest || Path.join([System.get_env("SPEC_HANDOFF_DIR") || raise("Provide --dest or set SPEC_HANDOFF_DIR"), id, "inbox"])
    Mix.Task.run("spec.msg.push", ["--id", id, "--dest", dest_inbox])
    Mix.Task.run("spec.thread.render", ["--id", id])
  end

  defp ref_opts(opts) do
    r = []
    r = if v = Keyword.get(opts, :ref_path), do: r ++ ["--ref-path", v], else: r
    r = if v = Keyword.get(opts, :ref_pointer), do: r ++ ["--ref-pointer", v], else: r
    r
  end

  defp req!(opts, key), do: Keyword.get(opts, key) || Mix.raise("Missing --#{key}")
end
