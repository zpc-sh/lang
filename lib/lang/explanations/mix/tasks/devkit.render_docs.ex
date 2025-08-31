defmodule Mix.Tasks.Devkit.RenderDocs do
  use Mix.Task
  @shortdoc "Render Markdown docs from JSON‑LD models in priv/dev/jsonld (dev‑only)"

  @moduledoc """
  Scans `priv/dev/jsonld` for `*.json` files using `Lang.Native.FSScanner`,
  validates and hashes the JSON‑LD, records/updates the dev `ModelRegistry` (ETS),
  and writes deterministic Markdown docs with frontmatter under `priv/docs/rendered/`.

  Usage:
    mix devkit.render_docs            # render all models under priv/dev/jsonld
    mix devkit.render_docs --id <id>  # render a specific model ID (by file name or lds:action)

  Notes:
  - Dev‑only; avoid running in prod. Honors `:dev_routes` setting defensively.
  - File reading uses FSScanner.preview; writing uses File.write with care.
  """

  alias Lang.Dev.{JSONLDHelper, ModelRegistry}
  import Ash.Query
  alias Lang.Dev.DocRenderer

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    unless Application.get_env(:lang, :dev_routes) do
      Mix.shell().error("dev_routes disabled; refusing to render in non‑dev mode.")
      exit({:shutdown, 1})
    end

    opts = parse_args(args)
    dir = Lang.Dev.Config.jsonld_dir()

    files =
      case opts[:id] do
        nil -> list_json_files(dir)
        id -> filter_by_id(dir, id)
      end

    if files == [] do
      Mix.shell().info("No JSON‑LD files found in #{dir}.")
      exit(:normal)
    end

    Enum.each(files, &render_file/1)
  end

  defp render_file(path) do
    case Lang.Dev.Config.fs_adapter().preview(path, max_lines: 1_000_000) do
      {:ok, lines} ->
        json = Enum.join(lines, "\n")
        with {:ok, map} <- JSONLDHelper.parse(json),
             :ok <- Lang.Dev.Config.validator().validate(map) do
          id = JSONLDHelper.model_id(map, Path.rootname(Path.basename(path)))
          hash = JSONLDHelper.canonical_hash(map)
          version = current_version_for(id) || "0.1.0"
          meta = %{id: id, version: version, hash: hash, provenance: path, rendered_at: DateTime.utc_now()}
          markdown = DocRenderer.render_markdown(map, meta)

          case DocRenderer.write_markdown(id, markdown) do
            {:ok, out_path} ->
              upsert_registry!(id, version, hash, path, meta.rendered_at)
              Mix.shell().info("Rendered #{id} -> #{out_path}")
            {:error, reason} ->
              Mix.shell().error("Failed to write doc for #{id}: #{inspect(reason)}")
          end
        else
          {:error, {:missing_keys, keys}} -> Mix.shell().error("Missing required keys in #{path}: #{inspect(keys)}")
          {:error, :invalid_json} -> Mix.shell().error("Invalid JSON in #{path}")
          other -> Mix.shell().error("Failed to render #{path}: #{inspect(other)}")
        end

      {:error, reason} ->
        Mix.shell().error("Failed to read #{path}: #{inspect(reason)}")
    end
  end

  defp upsert_registry!(id, version, hash, path, rendered_at) do
    case ModelRegistry.upsert(%{model_id: id, version: version, hash: hash, path: path, rendered_at: rendered_at}) do
      {:ok, _} -> :ok
      {:error, reason} -> raise "upsert failed for #{id}: #{inspect(reason)}"
    end
  end

  defp current_version_for(id) do
    case ModelRegistry |> filter(model_id == ^id) |> Ash.read() do
      {:ok, [%{version: v} | _]} -> v
      _ -> nil
    end
  end

  defp parse_args(args) do
    {opts, _argv, _} = OptionParser.parse(args, strict: [id: :string])
    Map.new(opts)
  end

  # jsonld_dir now provided by Lang.Dev.Config

  defp list_json_files(dir) do
    case Lang.Dev.Config.fs_adapter().scan(dir, max_depth: 1) do
      {:ok, %{tree: tree}} ->
        tree
        |> Enum.flat_map(fn
          %{"name" => name, "type" => "file"} -> [Path.join(dir, name)]
          %{name: name, type: "file"} -> [Path.join(dir, name)]
          %{name: name, type: :file} -> [Path.join(dir, name)]
          _ -> []
        end)
        |> Enum.filter(&String.ends_with?(&1, ".json"))
        |> Enum.sort()

      _ -> []
    end
  end

  defp filter_by_id(dir, id) do
    list_json_files(dir)
    |> Enum.filter(fn path -> Path.basename(path) == id <> ".json" end)
  end
end
