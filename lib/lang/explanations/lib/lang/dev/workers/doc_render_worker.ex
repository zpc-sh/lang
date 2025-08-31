defmodule Lang.Dev.Workers.DocRenderWorker do
  @moduledoc """
  Oban worker to (re)render a model's Markdown doc from its JSON‑LD provenance.
  - Emits telemetry spans and PubSub progress events under "dev:models".
  """

  use Oban.Worker, queue: :analysis, max_attempts: 3, tags: ["dev", "models", "render"]
  import Ash.Query
  require Logger

  alias Lang.Dev.{ModelRegistry, JSONLDHelper}
  alias Lang.Dev.DocRenderer
  alias Lang.Dev.ModelState

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"id" => id}}) when is_binary(id) do
    :telemetry.span([:lang, :dev_models, :render], %{id: id}, fn ->
      res = do_render(id)
      {res, %{id: id}}
    end)
  end

  defp do_render(id) do
    _ = Lang.Events.emit_dev_model_event(%{event_type: "render_start", model_id: id})

    case ModelRegistry |> filter(model_id == ^id) |> Ash.read() do
      {:ok, [%{path: path, version: version}]} ->
        with true <- safe_provenance?(path),
             {:ok, lines} <- Lang.Dev.Config.fs_adapter().preview(path, max_lines: 1_000_000),
             {:ok, map} <- JSONLDHelper.parse(Enum.join(lines, "\n")),
             :ok <- Lang.Dev.Config.validator().validate(map) do
          id = JSONLDHelper.model_id(map, id)
          hash = JSONLDHelper.canonical_hash(map)
          meta = %{id: id, version: version, hash: hash, provenance: path, rendered_at: DateTime.utc_now()}
          md = DocRenderer.render_markdown(map, meta)
          case DocRenderer.write_markdown(id, md) do
            {:ok, out} ->
              _ = ModelRegistry.upsert(%{model_id: id, version: version, hash: hash, path: path, rendered_at: meta.rendered_at})
              _ = Lang.Events.emit_dev_model_event(%{event_type: "render_done", model_id: id, path: out})
              _ = ModelState.record(%{model_id: id, version: version, hash: hash, status: current_status(id), path: path, event_type: "render_done", snapshot: map})
              :ok
            {:error, reason} ->
              _ = Lang.Events.emit_dev_model_event(%{event_type: "render_error", model_id: id, reason: inspect(reason)})
              {:error, inspect(reason)}
          end
        else
          false -> {:error, :invalid_provenance}
          {:error, reason} -> {:error, reason}
        end
      _ -> {:error, :not_found}
    end
  end

  defp current_status(id) do
    case ModelRegistry |> filter(model_id == ^id) |> Ash.read() do
      {:ok, [%{status: s} | _]} -> s
      _ -> nil
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
