defmodule LangWeb.DevModelsController do
  use LangWeb, :controller
  import Ash.Query
  require Logger

  alias Lang.Dev.{ModelRegistry, JSONLDHelper}
  alias Lang.Dev.DocRenderer

  # GET /dev/api/models
  def index(conn, _params) do
    with {:ok, models} <- ModelRegistry |> Ash.read() do
      json(conn, Enum.map(models, &summarize/1))
    else
      {:error, reason} -> conn |> put_status(:service_unavailable) |> json(%{error: inspect(reason)})
    end
  end

  # GET /dev/api/models/:id
  # Returns the JSON‑LD payload (decoded) with metadata for the model's provenance path
  def show(conn, %{"id" => id}) do
    case ModelRegistry |> filter(model_id == ^id) |> Ash.read() do
      {:ok, [rec | _]} ->
        path = rec.path
        with true <- safe_provenance?(path),
             {:ok, lines} <- Lang.Dev.Config.fs_adapter().preview(path, max_lines: 1_000_000),
             {:ok, map} <- JSONLDHelper.parse(Enum.join(lines, "\n")) do
          meta = summarize(rec) |> Map.put(:path, path)
          json(conn, %{jsonld: map, metadata: meta})
        else
          false -> conn |> put_status(:forbidden) |> json(%{error: "invalid_provenance"})
          {:error, reason} -> conn |> put_status(:not_found) |> json(%{error: inspect(reason)})
          {:error, :invalid_json} -> conn |> put_status(:bad_request) |> json(%{error: "invalid_json"})
          other -> conn |> put_status(:bad_request) |> json(%{error: inspect(other)})
        end
      _ -> conn |> put_status(:not_found) |> json(%{error: "not_found"})
    end
  end

  # GET /dev/api/models/drift
  # Compares registry hash with rendered doc frontmatter hash; lists mismatches
  def drift(conn, _params) do
    results = Lang.Dev.Drift.report()
    json(conn, %{drift: results})
  end

  # GET /dev/api/models/:id/history[?diff=1]
  def history(conn, %{"id" => id} = params) do
    with_diff = Map.get(params, "diff") in ["1", "true"]
    items = Lang.Dev.History.history(id, with_diff: with_diff)
    json(conn, %{id: id, history: items})
  end

  # GET /dev/api/models/:id/history/diff?entry_id=EID
  # GET /dev/api/models/:id/history/diff?from_id=A&to_id=B
  def diff(conn, %{"id" => id} = params) do
    case Lang.Dev.ModelState |> Ash.Query.filter(model_id == ^id) |> Ash.read() do
      {:ok, states} ->
        ordered = Enum.sort_by(states, & &1.at, DateTime)
        result =
          cond do
            is_binary(params["entry_id"]) -> do_diff_prev(ordered, params["entry_id"])
            is_binary(params["from_id"]) and is_binary(params["to_id"]) -> do_diff_pair(ordered, params["from_id"], params["to_id"])
            true -> {:error, :invalid_params}
          end

        case result do
          {:ok, diff} -> json(conn, diff)
          {:error, reason} -> conn |> put_status(:bad_request) |> json(%{error: inspect(reason)})
        end

      _ -> conn |> put_status(:not_found) |> json(%{error: "not_found"})
    end
  end

  defp do_diff_prev(list, eid) do
    idx = Enum.find_index(list, &(&1.id == eid))
    cond do
      is_nil(idx) -> {:error, :entry_not_found}
      idx == 0 -> {:ok, %{type: :root, before: nil, after: to_meta(Enum.at(list, 0)), diff: nil}}
      true ->
        prev = Enum.at(list, idx - 1)
        cur = Enum.at(list, idx)
        {:ok, %{before: to_meta(prev), after: to_meta(cur), diff: Lang.Dev.Diff.diff(prev.snapshot, cur.snapshot)}}
    end
  end

  defp do_diff_pair(list, from, to) do
    a = Enum.find(list, &(&1.id == from))
    b = Enum.find(list, &(&1.id == to))
    if a && b do
      {:ok, %{before: to_meta(a), after: to_meta(b), diff: Lang.Dev.Diff.diff(a.snapshot, b.snapshot)}}
    else
      {:error, :entry_not_found}
    end
  end

  defp to_meta(entry) do
    %{
      id: entry.id,
      version: entry.version,
      hash: entry.hash,
      status: entry.status,
      at: entry.at
    }
  end

  # POST /dev/api/models/:id/render
  # Re-render a single model doc based on provenance path
  def render_one(conn, %{"id" => id}) do
    job = Lang.Dev.Workers.DocRenderWorker.new(%{"id" => id}, queue: :analysis)
    case Oban.insert(job) do
      {:ok, %Oban.Job{id: jid}} -> conn |> put_status(:accepted) |> json(%{ok: true, enqueued: true, job_id: jid})
      {:error, reason} -> conn |> put_status(:service_unavailable) |> json(%{error: inspect(reason)})
    end
  end

  # POST /dev/api/models/ingest  with JSON body: {"id": "<model_id>"}
  def ingest(conn, params) do
    id = Map.get(params, "id")
    job = Lang.Dev.Workers.DocIngestWorker.new(%{"id" => id}, queue: :analysis)
    case Oban.insert(job) do
      {:ok, %Oban.Job{id: jid}} -> conn |> put_status(:accepted) |> json(%{ok: true, enqueued: true, job_id: jid})
      {:error, reason} -> conn |> put_status(:service_unavailable) |> json(%{error: inspect(reason)})
    end
  end

  # POST /dev/api/models/:id/status with JSON body: {"status": "ready", "owner": "alice", "notes": "..."}
  def status_update(conn, %{"id" => id} = params) do
    with {:ok, [%{version: ver, hash: hash, path: path} = rec]} <- ModelRegistry |> filter(model_id == ^id) |> Ash.read() do
      new_status = Map.get(params, "status", rec.status)
      if new_status && not valid_status?(rec.status, new_status) do
        conn |> put_status(:bad_request) |> json(%{error: "invalid_status_transition", from: rec.status, to: new_status})
      else
        now = DateTime.utc_now()
        changed = new_status && new_status != rec.status
        attrs = %{
          model_id: id,
          version: ver,
          hash: hash,
          path: path,
          rendered_at: Map.get(rec, :rendered_at),
          status: new_status,
          status_changed_at: if(changed, do: now, else: rec.status_changed_at),
          changed_by: Map.get(params, "changed_by", rec.changed_by),
          owner: Map.get(params, "owner", rec.owner),
          notes: Map.get(params, "notes", rec.notes)
        }
        case ModelRegistry.upsert(attrs) do
          {:ok, _} ->
            _ = if(changed, do: Lang.Events.emit_dev_model_event(%{event_type: "status_updated", model_id: id, status: new_status}), else: :ok)
            # Record a state snapshot for history
            _ =
              case Lang.Dev.Config.fs_adapter().preview(path, max_lines: 1_000_000) do
                {:ok, lines} ->
                  with {:ok, map} <- JSONLDHelper.parse(Enum.join(lines, "\n")) do
                    _ = Lang.Dev.ModelState.record(%{model_id: id, version: ver, hash: hash, status: new_status, path: path, event_type: "status_updated", snapshot: map, actor: Map.get(params, "changed_by")})
                    :ok
                  else
                    _ -> :ok
                  end
                _ -> :ok
              end
            json(conn, %{ok: true})
          {:error, reason} -> conn |> put_status(:bad_request) |> json(%{error: inspect(reason)})
        end
      end
    else
      _ -> conn |> put_status(:not_found) |> json(%{error: "not_found"})
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

  defp valid_status?(from, to) do
    allowed = %{
      nil => ["draft", "ready", "implemented", "deprecated"],
      "draft" => ["ready", "deprecated"],
      "ready" => ["implemented", "deprecated"],
      "implemented" => ["deprecated"],
      "deprecated" => []
    }
    Enum.member?(Map.get(allowed, from, []), to)
  end

  defp summarize(%{model_id: id, version: version, hash: hash} = rec) do
    %{
      id: id,
      version: version,
      hash: hash,
      status: Map.get(rec, :status),
      status_changed_at: Map.get(rec, :status_changed_at),
      changed_by: Map.get(rec, :changed_by),
      owner: Map.get(rec, :owner),
      notes: Map.get(rec, :notes)
    }
  end

  # drift logic moved to Lang.Dev.Drift
end
