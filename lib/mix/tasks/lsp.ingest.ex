defmodule Mix.Tasks.Lsp.Ingest do
  use Mix.Task
  @shortdoc "Ingest a JSON-LD spec into Ash (canonical store)"
  @moduledoc """
  Usage:
    mix lsp.ingest priv/lsp/specs/method.jsonld
  """

  alias Nullity.CDFM.Spec
  alias Nullity.CDFM.Adapters.Store.Ash

  @impl true
  def run(args) do
    # Load paths without compiling the whole app
    Mix.Task.run("loadpaths")

    {opts, rest, _} = OptionParser.parse(args, switches: [dry_run: :boolean])

    case rest do
      [path] ->
        with {:ok, bin} <- read_file(path), specs <- Spec.parse_spec!(bin) do
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
                {:ok, _} -> Mix.shell().info("ingested: #{s.name}")
                {:error, reason} -> Mix.shell().error("failed: #{inspect(reason)}")
              end
            end
          end)
        else
          {:error, reason} -> Mix.raise("failed to read #{path}: #{inspect(reason)}")
        end

      _ ->
        Mix.raise("usage: mix lsp.ingest [--dry-run] path/to/spec.jsonld")
    end
  end

  defp read_file(path) do
    # Use standard File here for simplicity; swap to FSScanner if needed
    File.read(path)
  end
end
