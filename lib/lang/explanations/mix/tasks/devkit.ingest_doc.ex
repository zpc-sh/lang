defmodule Mix.Tasks.Devkit.IngestDoc do
  use Mix.Task
  @shortdoc "Ingest a rendered doc back into JSON‑LD (dev‑only, gated)"

  @moduledoc """
  Parses a rendered Markdown doc, validates frontmatter and content, and updates the JSON‑LD provenance
  file only when safe rules pass. Does not infer from free text; only uses the JSON block content.

      mix devkit.ingest_doc --id <model_id>

  Rules:
  - Frontmatter must include id, version, hash; id must match `--id` (if provided).
  - The canonical hash of the JSON block must equal the frontmatter hash.
  - If the new hash differs from the registry hash, the frontmatter version must be strictly greater.
  - On success: writes JSON‑LD to provenance path, updates registry, and re-renders doc deterministically.
  """

  import Ash.Query
  alias Lang.Dev.{DocRenderer, JSONLDHelper, ModelRegistry}

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    unless Application.get_env(:lang, :dev_routes) do
      Mix.shell().error("dev_routes disabled; refusing to ingest in non‑dev mode.")
      exit({:shutdown, 1})
    end

    opts = parse_args(args)
    id = opts[:id] || abort!("--id <model_id> is required")

    doc_path = Path.join(DocRenderer.output_dir(), id <> ".md")
    case File.read(doc_path) do
      {:ok, markdown} -> ingest_markdown(id, markdown)
      {:error, reason} -> abort!("failed to read doc: #{inspect(reason)}")
    end
  end

  defp ingest_markdown(id, markdown) do
    with {:ok, fm, body} <- DocRenderer.parse_frontmatter(markdown),
         ^id <- Map.get(fm, "id") || abort!("frontmatter id mismatch"),
         {:ok, json_map} <- DocRenderer.extract_json(body),
         :ok <- Lang.Dev.Config.validator().validate(json_map) do

      new_hash = JSONLDHelper.canonical_hash(json_map)
      fm_hash = Map.get(fm, "hash")
      version = Map.get(fm, "version")

      unless is_binary(fm_hash) and fm_hash == new_hash do
        abort!("hash mismatch: frontmatter=#{inspect(fm_hash)} computed=#{new_hash}")
      end

      case ModelRegistry |> filter(model_id == ^id) |> Ash.read() do
        {:ok, [%{hash: reg_hash, version: reg_ver, path: path}]} ->
          do_ingest(id, json_map, new_hash, version, reg_hash, reg_ver, path)
        _ -> abort!("model not found in registry: #{id}")
      end
    else
      {:error, {:missing_keys, keys}} -> abort!("missing required keys: #{inspect(keys)}")
      {:error, {:invalid_action_id, _}} -> abort!("invalid lds:action")
      {:error, :invalid_json_block} -> abort!("invalid JSON in code block")
      {:error, :json_block_not_found} -> abort!("no JSON code block found")
      {:error, :invalid_frontmatter} -> abort!("invalid frontmatter")
      other -> abort!("ingest failed: #{inspect(other)}")
    end
  end

  defp do_ingest(id, json_map, new_hash, new_ver, reg_hash, reg_ver, path) do
    cond do
      new_hash == reg_hash ->
        Mix.shell().info("No changes detected for #{id}; hashes match.")
      version_lte?(new_ver, reg_ver) ->
        abort!("version must be bumped: current=#{reg_ver} new=#{new_ver}")
      not safe_provenance?(path) ->
        abort!("invalid provenance path")
      true ->
        json_text = Jason.encode!(json_map, pretty: true)
        case File.write(path, json_text) do
          :ok ->
            # Update registry and re-render
            now = DateTime.utc_now()
            {:ok, _} = ModelRegistry.upsert(%{model_id: id, version: new_ver, hash: new_hash, path: path, rendered_at: now})
            md = DocRenderer.render_markdown(json_map, %{id: id, version: new_ver, hash: new_hash, provenance: path, rendered_at: now})
            case DocRenderer.write_markdown(id, md) do
              {:ok, out} -> Mix.shell().info("Ingested #{id}; JSON‑LD updated and doc re-rendered -> #{out}")
              {:error, reason} -> abort!("updated JSON‑LD but failed to write doc: #{inspect(reason)}")
            end
          {:error, reason} -> abort!("failed to write JSON‑LD: #{inspect(reason)}")
        end
    end
  end

  defp parse_args(args) do
    {opts, _argv, _} = OptionParser.parse(args, strict: [id: :string])
    Map.new(opts)
  end

  defp version_lte?(a, b), do: version_cmp(a, b) in [:lt, :eq]

  defp version_cmp(a, b) do
    parse = fn v ->
      case String.split(to_string(v), ".") |> Enum.map(&parse_int/1) do
        [maj, min, pat] -> {maj, min, pat}
        [maj, min] -> {maj, min, 0}
        [maj] -> {maj, 0, 0}
        _ -> {0, 0, 0}
      end
    end
    {a1, a2, a3} = parse.(a)
    {b1, b2, b3} = parse.(b)
    cond do
      a1 < b1 -> :lt
      a1 > b1 -> :gt
      a2 < b2 -> :lt
      a2 > b2 -> :gt
      a3 < b3 -> :lt
      a3 > b3 -> :gt
      true -> :eq
    end
  end

  defp parse_int(str) do
    case Integer.parse(to_string(str)) do
      {n, _} -> n
      :error -> 0
    end
  end

  defp safe_provenance?(path) when is_binary(path) do
    base =
      :code.priv_dir(:lang)
      |> to_string()
      |> Path.join(["dev", "jsonld"])
      |> Path.expand()

    full = Path.expand(path)
    String.starts_with?(full, base)
  end

  defp abort!(msg) do
    Mix.shell().error(to_string(msg))
    exit({:shutdown, 1})
  end
end
