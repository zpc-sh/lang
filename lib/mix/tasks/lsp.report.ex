defmodule Mix.Tasks.Lsp.Report do
  use Mix.Task
  @shortdoc "Ingest specs and print coverage report"

  @moduledoc """
  Runs the JSON-LD LSP spec ingestion (to Ash when available) and then prints
  a coverage report comparing specs to dispatch handlers.

      mix lsp.report
  """

  @impl true
  def run(_args) do
    Mix.Task.run("loadpaths")

    # Ingest default directory
    Mix.shell().info("[lsp.report] Ingesting specs from priv/lsp/specs …")

    try do
      Mix.Task.run("lsp.ingest_dir", ["priv/lsp/specs"])
    rescue
      _ -> :ok
    end

    Mix.shell().info("[lsp.report] Coverage …")
    Mix.Task.run("lsp.coverage", [])
  end
end
