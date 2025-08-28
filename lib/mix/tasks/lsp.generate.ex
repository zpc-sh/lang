defmodule Mix.Tasks.Lsp.Generate do
  use Mix.Task
  @shortdoc "Generate handlers, registry, and docs from stored LSP methods"

  alias Nullity.CDFM.LSPProjectGenerator
  alias Nullity.CDFM.Adapters.Store.Ash
  alias Nullity.CDFM.Adapters.FileAdapter.FSScanner

  @impl true
  def run(args) do
    # Load paths without compiling the whole app
    Mix.Task.run("loadpaths")
    {opts, _rest, _} = OptionParser.parse(args, switches: [dry_run: :boolean])

    with {:ok, methods} <- Ash.read_all_methods(),
         blueprints <- Enum.map(methods, &to_blueprint/1),
         {:ok, %{files: files}} <- LSPProjectGenerator.generate_all(blueprints) do
      if opts[:dry_run] do
        Enum.each(files, fn %{path: path} -> Mix.shell().info("[dry-run] would write: #{path}") end)
        Mix.shell().info("[dry-run] total files: #{length(files)}")
      else
        Enum.each(files, &write!/1)
        Mix.shell().info("Generated #{length(files)} files")
      end
    else
      {:error, reason} -> Mix.raise("generation failed: #{inspect(reason)}")
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
