defmodule Mix.Tasks.Spec.Push do
  use Mix.Task
  @shortdoc "Copy a spec request folder to a destination handoff directory"
  @moduledoc """
  Usage:
    mix spec.push --id <request_id> [--dest /path/to/other/repo/work/spec_requests]

  Destination defaults to SPEC_HANDOFF_DIR env var if not provided.
  """

  @impl true
  def run(argv) do
    {opts, _, _} = OptionParser.parse(argv, switches: [id: :string, dest: :string])
    id = require!(opts, :id)
    dest = Keyword.get(opts, :dest) || System.get_env("SPEC_HANDOFF_DIR") || Mix.raise("Provide --dest or set SPEC_HANDOFF_DIR")

    src_root = Path.join(["work", "spec_requests", id])
    File.dir?(src_root) || Mix.raise("Request not found: #{src_root}")

    dest_root = Path.join(dest, id)
    File.mkdir_p!(dest_root)

    copy_tree!(src_root, dest_root)
    Mix.shell().info("Pushed #{id} -> #{dest_root}")
  end

  defp copy_tree!(src, dst) do
    for path <- Path.wildcard(Path.join(src, "**/*"), match_dot: true) do
      rel = Path.relative_to(path, src)
      target = Path.join(dst, rel)
      cond do
        File.dir?(path) -> File.mkdir_p!(target)
        File.regular?(path) ->
          File.mkdir_p!(Path.dirname(target))
          File.cp!(path, target)
        true -> :ok
      end
    end
  end

  defp require!(opts, key), do: Keyword.get(opts, key) || Mix.raise("Missing --#{key}")
end
