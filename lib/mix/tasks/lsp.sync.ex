defmodule Mix.Tasks.Lsp.Sync do
  use Mix.Task
  @shortdoc "Recompute derived statuses and regenerate docs"

  alias Nullity.CDFM.Sync
  alias Nullity.CDFM.Adapters.FileAdapter.FSScanner
  alias Nullity.CDFM.Adapters.Store.Ash
  alias Nullity.CDFM.Adapters.Introspection.Code
  alias Nullity.CDFM.LSPProjectGenerator

  @impl true
  def run(_args) do
    # Only load paths; avoid compiling unrelated modules that may fail
    Mix.Task.run("loadpaths")

    :ok = Sync.sync_all(file_adapter: FSScanner, store: Ash, introspection: Code)

    # Regenerate docs from updated statuses
    with {:ok, methods} <- Ash.read_all_methods(),
         {:ok, %{files: files}} <- LSPProjectGenerator.generate_all(Enum.map(methods, &to_blueprint/1)) do
      doc = Enum.find(files, &(&1.path == "docs/lsp.md"))
      if doc, do: write!(doc)
      Mix.shell().info("Synced statuses and docs")
    else
      {:error, reason} -> Mix.shell().error("docs generation failed: #{inspect(reason)}")
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
