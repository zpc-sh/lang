defmodule Mix.Tasks.Lsp.IngestDir do
  use Mix.Task
  @shortdoc "Ingest all JSON-LD specs from a directory into Ash"
  @moduledoc """
  Usage:
    mix lsp.ingest_dir priv/lsp/specs
  """

  alias Lang.Native.FSScanner
  alias Nullity.CDFM.Spec
  alias Nullity.CDFM.Adapters.Store.Ash

  @impl true
  def run(args) do
    # Load paths without compiling the whole app
    Mix.Task.run("loadpaths")
    {opts, rest, _} = OptionParser.parse(args, switches: [dry_run: :boolean])
    case rest do
      [dir] ->
        files = jsonld_files(dir)
        Enum.each(files, &ingest_file(&1, opts))
      _ -> Mix.raise("usage: mix lsp.ingest_dir [--dry-run] path/to/specs_dir")
    end
  end

  defp jsonld_files(dir) do
    # Prefer native FS search; fall back to Path.wildcard if NIFs unavailable
    case FSScanner.search(dir, ~S/\.(jsonld|ya?ml)$/, max_results: 10_000) do
      {:ok, results} when is_list(results) ->
        Enum.map(results, fn
          %{:path => path} -> path
          %{"path" => path} -> path
          path when is_binary(path) -> path
        end)

      _ ->
        patterns = ["**/*.jsonld", "**/*.yaml", "**/*.yml"]
        Enum.flat_map(patterns, fn pat -> Path.wildcard(Path.join(dir, pat)) end)
    end
  end

  defp ingest_file(path, opts) do
    case File.read(path) do
      {:ok, bin} -> ingest_content(bin, opts)
      {:error, reason} -> Mix.shell().error("failed to read #{path}: #{inspect(reason)}")
    end
  end

  defp ingest_content(content, opts) do
    specs = Spec.parse_jsonld!(content)
    Enum.each(specs, fn s ->
      attrs = %{
        name: s.name,
        category: s.category,
        description: s.description,
        priority: s.priority,
        spec_status: s.spec_status,
        impl_file: s.impl_file,
        impl_module: s.impl_module,
        impl_function: s.impl_function,
        impl_arity: s.impl_arity,
        params_schema: s.params_schema,
        result_schema: s.result_schema,
        links: s.links,
        metadata: s.metadata
      }
      if opts[:dry_run] do
        Mix.shell().info("[dry-run] would ingest: #{s.name}")
      else
        case Ash.upsert_method(attrs) do
          {:ok, _} -> :ok
          {:error, reason} -> Mix.shell().error("failed upsert #{s.name}: #{inspect(reason)}")
        end
      end
    end)
  end
end
