defmodule Mix.Tasks.Lsp.Docs do
  use Mix.Task
  @shortdoc "Regenerate LSP docs from stored methods"

  alias Nullity.CDFM.LSPProjectGenerator
  alias Nullity.CDFM.Adapters.Store.Ash
  alias Nullity.CDFM.Adapters.FileAdapter.FSScanner

  @impl true
  def run(_args) do
    Mix.Task.run("app.start")

    with {:ok, methods} <- Ash.read_all_methods(),
         {:ok, %{files: files}} <-
           LSPProjectGenerator.generate_all(Enum.map(methods, &to_blueprint/1)) do
      doc = Enum.find(files, &(&1.path == "docs/lsp.md"))
      if doc, do: write!(doc)
      Mix.shell().info("Regenerated docs/lsp.md")
    else
      {:error, reason} -> Mix.raise("docs generation failed: #{inspect(reason)}")
    end
  end

  defp write!(%{path: path, content: content}) do
    case FSScanner.write(path, content) do
      :ok -> :ok
      {:error, reason} -> Mix.raise("write failed #{path}: #{inspect(reason)}")
    end
  end

  defp to_blueprint(m) do
    %{
      name: m[:name],
      category: m[:category],
      description: m[:description],
      priority: m[:priority],
      derived_status: m[:derived_status],
      impl_file: m[:impl_file],
      impl_module: m[:impl_module],
      impl_function: m[:impl_function],
      impl_arity: m[:impl_arity]
    }
  end
end
