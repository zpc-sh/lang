defmodule Mix.Tasks.Devkit.LintInjection do
  use Mix.Task
  @shortdoc "Scan rendered docs for prompt/log injection patterns; fails on findings"

  @moduledoc """
  Scans `priv/docs/rendered/*.md` with heuristic rules to flag potential injection content.

      mix devkit.lint_injection

  Exits non-zero if any findings are detected.
  """

  alias Lang.Dev.DocRenderer
  alias Lang.Dev.InjectionScanner

  @impl true
  def run(_args) do
    Mix.Task.run("app.start")

    dir = DocRenderer.output_dir()
    files = File.ls!(dir) |> Enum.filter(&String.ends_with?(&1, ".md")) |> Enum.map(&Path.join(dir, &1))

    findings =
      files
      |> Enum.flat_map(fn path ->
        case File.read(path) do
          {:ok, content} ->
            InjectionScanner.scan_markdown(content)
            |> Enum.map(&Map.put(&1, :file, Path.basename(path)))
          _ -> []
        end
      end)

    if findings == [] do
      Mix.shell().info("Injection lint passed: no findings.")
    else
      Enum.each(findings, fn f ->
        Mix.shell().info("- [#{f.severity}] #{f.file}:#{f.line} #{f.type} :: #{f.snippet}")
      end)
      Mix.shell().error("Injection lint failed: #{length(findings)} findings.")
      exit({:shutdown, 1})
    end
  end
end

