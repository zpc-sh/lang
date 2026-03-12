defmodule Mix.Tasks.Spec.Hub.Sync do
  use Mix.Task
  @shortdoc "Sync a local request folder into a spec-hub under requests/<project>/<id>"
  @moduledoc """
  Usage:
    mix spec.hub.sync --id <request_id> --project <name> --hub ../lang-spec-hub \
                      [--api https://cdfm.example.com] [--token <api-token>] [--since <iso8601>] [--no-pull] [--no-validate]

  Copies `work/spec_requests/<id>` to `<hub>/requests/<project>/<id>` (creating directories as needed).
  Does not copy inbound/outbound transport unless present; preserves structure.
  Re-renders thread.md before copy to ensure up-to-date.
  """

  @impl true
  def run(argv) do
    {opts, _, _} = OptionParser.parse(argv, switches: [
      id: :string,
      project: :string,
      hub: :string,
      no_export: :boolean,
      no_index: :boolean,
      validate: :boolean, # kept for backward-compat; default is validate=true
      no_validate: :boolean,
      api: :string,
      token: :string,
      since: :string,
      no_pull: :boolean
    ])
    id = req!(opts, :id)
    project = req!(opts, :project)
    hub = req!(opts, :hub)

    # Optional: pull latest from CDFM before rendering/syncing
    case Keyword.get(opts, :api) do
      nil -> :ok
      api ->
        token = Keyword.get(opts, :token) || System.get_env("CDFM_API_TOKEN")
        unless Keyword.get(opts, :no_pull, false) do
          args = ["--id", id, "--api", api] ++ (token && ["--token", token] || []) ++
                   (Keyword.get(opts, :since) && ["--since", Keyword.get(opts, :since)] || [])
          Mix.Task.run("spec.msg.pull", args)
        end
    end

    # Ensure thread is current
    Mix.Task.run("spec.thread.render", ["--id", id])

    src = Path.join([File.cwd!(), "work", "spec_requests", id])
    File.dir?(src) || Mix.raise("Missing local request folder: #{src}")

    dest = Path.join([hub, "requests", project, id])
    File.mkdir_p!(dest)
    copy_tree!(src, dest)

    unless Keyword.get(opts, :no_export, false) do
      export_extra = case Keyword.get(opts, :api) do
        nil -> []
        api ->
          token = Keyword.get(opts, :token) || System.get_env("CDFM_API_TOKEN")
          ["--api", api] ++ (token && ["--token", token] || [])
      end
      Mix.Task.reenable("spec.export.jsonld")
      Mix.Task.run("spec.export.jsonld", ["--id", id, "--project", project, "--hub", hub] ++ export_extra)
    end

    unless Keyword.get(opts, :no_index, false) do
      Mix.Task.run("spec.index", ["--hub", hub])
    end

    unless Keyword.get(opts, :no_validate, false) do
      Mix.Task.reenable("spec.hub.validate")
      Mix.Task.run("spec.hub.validate", ["--id", id, "--project", project, "--hub", hub])
    end

    Mix.shell().info(
      "Synced #{id} -> #{dest}" <>
        (Keyword.get(opts, :no_export, false) && "" || " (JSON-LD exported") <>
        (Keyword.get(opts, :no_index, false) && ")" || ", index refreshed)")
    )
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

  defp req!(opts, key), do: Keyword.get(opts, key) || Mix.raise("Missing --#{key}")
end
