defmodule Lang.Dev.Workers.DocIngestWorker do
  @moduledoc """
  Oban worker to ingest a rendered doc back into JSON‑LD (dev‑only, gated).
  - Validates frontmatter and JSON block; requires version bump on content changes.
  - Emits telemetry and PubSub events under "dev:models".
  """

  use Oban.Worker, queue: :analysis, max_attempts: 3, tags: ["dev", "models", "ingest"]
  import Ash.Query

  alias Lang.Dev.{DocRenderer, JSONLDHelper, ModelRegistry}
  alias Lang.Dev.ModelState

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"id" => id}}) when is_binary(id) do
    :telemetry.span([:lang, :dev_models, :ingest], %{id: id}, fn ->
      res = do_ingest(id)
      {res, %{id: id}}
    end)
  end

  defp do_ingest(id) do
    _ = Lang.Events.emit_dev_model_event(%{event_type: "ingest_start", model_id: id})

    case ModelRegistry |> filter(model_id == ^id) |> Ash.read() do
      {:ok, [%{hash: reg_hash, version: reg_ver, path: path}]} ->
        with true <- safe_provenance?(path),
             {:ok, markdown} <- File.read(Path.join(DocRenderer.output_dir(), id <> ".md")),
             {:ok, fm, body} <- DocRenderer.parse_frontmatter(markdown),
             ^id <- Map.get(fm, "id"),
             {:ok, json_map} <- DocRenderer.extract_json(body),
             :ok <- Lang.Dev.Config.validator().validate(json_map) do
          new_hash = JSONLDHelper.canonical_hash(json_map)
          fm_hash = Map.get(fm, "hash")
          new_ver = Map.get(fm, "version")

          cond do
            not is_binary(fm_hash) or fm_hash != new_hash ->
              _ = Lang.Events.emit_dev_model_event(%{event_type: "ingest_error", model_id: id, reason: "hash_mismatch"})
              {:error, :hash_mismatch}
            version_lte?(new_ver, reg_ver) ->
              _ = Lang.Events.emit_dev_model_event(%{event_type: "ingest_error", model_id: id, reason: "version_not_bumped"})
              {:error, :version_not_bumped}
            true ->
              json_text = Jason.encode!(json_map, pretty: true)
              case File.write(path, json_text) do
                :ok ->
                  now = DateTime.utc_now()
                  {:ok, _} = ModelRegistry.upsert(%{model_id: id, version: new_ver, hash: new_hash, path: path, rendered_at: now})
                  md = DocRenderer.render_markdown(json_map, %{id: id, version: new_ver, hash: new_hash, provenance: path, rendered_at: now})
                  case DocRenderer.write_markdown(id, md) do
                    {:ok, out} ->
                      _ = Lang.Events.emit_dev_model_event(%{event_type: "ingest_done", model_id: id, path: out})
                      _ = ModelState.record(%{model_id: id, version: new_ver, hash: new_hash, status: current_status(id), path: path, event_type: "ingest_done", snapshot: json_map})
                      :ok
                    {:error, reason} ->
                      _ = Lang.Events.emit_dev_model_event(%{event_type: "ingest_error", model_id: id, reason: inspect(reason)})
                      {:error, inspect(reason)}
                  end
                {:error, reason} ->
                  _ = Lang.Events.emit_dev_model_event(%{event_type: "ingest_error", model_id: id, reason: inspect(reason)})
                  {:error, inspect(reason)}
              end
          end
        else
          false -> {:error, :invalid_provenance}
          {:error, reason} -> {:error, reason}
        end
      _ -> {:error, :not_found}
    end
  end

  defp current_status(id) do
    case Lang.Dev.ModelRegistry |> Ash.Query.filter(model_id == ^id) |> Ash.read() do
      {:ok, [%{status: s} | _]} -> s
      _ -> nil
    end
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

  defp safe_provenance?(path) do
    base =
      :code.priv_dir(:lang)
      |> to_string()
      |> Path.join(["dev", "jsonld"])
      |> Path.expand()

    full = Path.expand(path)
    String.starts_with?(full, base)
  end
end

