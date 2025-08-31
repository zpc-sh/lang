defmodule Mix.Tasks.Devkit.LintDocs do
  use Mix.Task
  @shortdoc "Lint docs by rendering and checking drift; exits nonzero on mismatch"

  @moduledoc """
  Renders docs deterministically (unless --no-render) and checks drift between
  the dev ModelRegistry and rendered Markdown frontmatter. Exits with non‑zero
  status if any drift is detected.

      mix devkit.lint_docs
      mix devkit.lint_docs --no-render
  """

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    opts = parse_args(args)
    unless opts[:no_render] do
      Mix.Task.rerun("devkit.render_docs")
    end

    drift = Lang.Dev.Drift.report()
    if drift == [] do
      Mix.shell().info("Docs lint passed: no drift detected.")
      :ok
    else
      print_drift(drift)
      Mix.shell().error("Docs lint failed: drift detected (#{length(drift)}).")
      exit({:shutdown, 1})
    end
  end

  defp parse_args(args) do
    {opts, _argv, _} = OptionParser.parse(args, strict: ["no-render": :boolean])
    %{no_render: Keyword.get(opts, :"no-render", false)}
  end

  defp print_drift(items) do
    Enum.each(items, fn %{id: id, registry_hash: r, doc_hash: d} ->
      Mix.shell().info("- #{id}: registry=#{r} doc=#{inspect(d)}")
    end)
  end
end

