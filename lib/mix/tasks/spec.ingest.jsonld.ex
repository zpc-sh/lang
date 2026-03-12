defmodule Mix.Tasks.Spec.Ingest.Jsonld do
  use Mix.Task
  @shortdoc "Ingest JSON-LD docs from hub (c14n/hash stub)"
  @moduledoc """
  Usage:
    mix spec.ingest.jsonld --project <name> --id <req> --hub ../lang-spec-hub

  Loads JSON-LD documents from `<hub>/requests/<project>/<id>/jsonld/`, computes a deterministic
  hash (stable JSON fallback), and writes `hashes.json`. Ready to be wired to Kyozo/CDFM.
  """

  alias MarkdownLD.Hash, as: LDHash

  @impl true
  def run(argv) do
    {opts, _, _} = OptionParser.parse(argv, switches: [project: :string, id: :string, hub: :string])
    project = req!(opts, :project)
    id = req!(opts, :id)
    hub = req!(opts, :hub)

    dir = Path.join([hub, "requests", project, id, "jsonld"]) 
    File.dir?(dir) || Mix.raise("JSON-LD dir not found: #{dir}")

    docs = Path.wildcard(Path.join(dir, "**/*.jsonld"))
    results =
      Enum.map(docs, fn path ->
        {:ok, integrity} = LDHash.dataset_hash(read_json!(path))
        %{file: Path.relative_to(path, dir), hash: integrity[:hash], form: integrity[:form]}
      end)

    out = %{project: project, id: id, docs: results, updated_at: DateTime.utc_now() |> DateTime.to_iso8601()}
    File.write!(Path.join(dir, "hashes.json"), Jason.encode_to_iodata!(out, pretty: true))
    Mix.shell().info("Ingested #{length(results)} JSON-LD doc(s). hashes.json written.")
  end

  defp read_json!(path), do: Jason.decode!(File.read!(path))
  defp req!(opts, key), do: Keyword.get(opts, key) || Mix.raise("Missing --#{key}")
end
