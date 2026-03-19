defmodule Mix.Tasks.Spec.Export.Tools do
  use Mix.Task
  @shortdoc "Copy Mix spec tasks and schemas into another repo for replication"
  @moduledoc """
  Usage:
    mix spec.export.tools --dest /path/to/other/repo

  Copies sender/receiver Mix tasks and required schemas so the other repo can
  participate fully in the handoff flow.
  """

  @task_glob ~w(
    lib/mix/tasks/spec.*.ex
  )

  @impl true
  def run(argv) do
    {opts, _, _} = OptionParser.parse(argv, switches: [dest: :string])
    dest = Keyword.get(opts, :dest) || Mix.raise("Provide --dest")

    # Copy tasks
    for path <- Path.wildcard(Path.join([File.cwd!(), "lib/mix/tasks", "spec.*.ex"])) do
      copy!(path, Path.join(dest, "lib/mix/tasks/" <> Path.basename(path)))
    end

    # Copy schemas and receiver docs
    Mix.Task.reenable("spec.export.docs")
    Mix.Task.run("spec.export.docs", ["--dest", dest])
    Mix.shell().info("Exported spec tools to #{dest}")
  end

  defp copy!(src, dst) do
    File.mkdir_p!(Path.dirname(dst))
    File.cp!(src, dst)
  end
end
