defmodule Lang.LSP.Dev.Models.List do
  @behaviour Lang.LSP.Handler
  import Ash.Query
  def method, do: "lang.dev.models.list"
  def handle(_params, _ctx) do
    if Application.get_env(:lang, :dev_routes) do
      case Lang.Dev.ModelRegistry |> Ash.read() do
        {:ok, list} ->
          {:ok,
           Enum.map(list, fn rec ->
             %{
               id: rec.model_id,
               version: rec.version,
               hash: rec.hash,
               status: rec.status,
               owner: rec.owner,
               status_changed_at: rec.status_changed_at,
               changed_by: rec.changed_by
             }
           end)}
        {:error, reason} -> {:error, inspect(reason)}
      end
    else
      {:error, :dev_routes_disabled}
    end
  end
end

defmodule Lang.LSP.Dev.Models.Get do
  @behaviour Lang.LSP.Handler
  import Ash.Query
  def method, do: "lang.dev.models.get"
  def handle(%{"id" => id}, _ctx) do
    if Application.get_env(:lang, :dev_routes) do
      case Lang.Dev.ModelRegistry |> filter(model_id == ^id) |> Ash.read() do
        {:ok, [rec | _]} ->
          path = rec.path
          with true <- safe_provenance?(path),
               {:ok, lines} <- Lang.Dev.Config.fs_adapter().preview(path, max_lines: 1_000_000),
               {:ok, map} <- Lang.Dev.JSONLDHelper.parse(Enum.join(lines, "\n")) do
            meta = %{
              id: rec.model_id,
              version: rec.version,
              hash: rec.hash,
              status: rec.status,
              owner: rec.owner,
              status_changed_at: rec.status_changed_at,
              changed_by: rec.changed_by,
              path: path
            }
            {:ok, %{jsonld: map, metadata: meta}}
          else
            false -> {:error, :invalid_provenance}
            {:error, reason} -> {:error, inspect(reason)}
            other -> other
          end
        _ -> {:error, :not_found}
      end
    else
      {:error, :dev_routes_disabled}
    end
  end
  def handle(_, _), do: {:error, :invalid_params}

  defp safe_provenance?(path) do
    base = Lang.Dev.Config.jsonld_dir()
    String.starts_with?(Path.expand(path), base)
  end
end

defmodule Lang.LSP.Dev.Models.History do
  @behaviour Lang.LSP.Handler
  def method, do: "lang.dev.models.history"
  def handle(%{"id" => id} = params, _ctx) do
    if Application.get_env(:lang, :dev_routes) do
      with_diff = Map.get(params, "diff") in ["1", "true", 1, true]
      items = Lang.Dev.History.history(id, with_diff: with_diff)
      {:ok, %{id: id, history: items}}
    else
      {:error, :dev_routes_disabled}
    end
  end
  def handle(_, _), do: {:error, :invalid_params}
end

defmodule Lang.LSP.Dev.Models.Render do
  @behaviour Lang.LSP.Handler
  def method, do: "lang.dev.models.render"
  def handle(%{"id" => id}, _ctx) do
    if Application.get_env(:lang, :dev_routes) do
      case Lang.Dev.Workers.DocRenderWorker.new(%{"id" => id}, queue: :analysis) |> Oban.insert() do
        {:ok, %Oban.Job{id: jid}} -> {:ok, %{enqueued: true, job_id: jid}}
        {:error, reason} -> {:error, inspect(reason)}
      end
    else
      {:error, :dev_routes_disabled}
    end
  end
  def handle(_, _), do: {:error, :invalid_params}
end

defmodule Lang.LSP.Dev.Models.Ingest do
  @behaviour Lang.LSP.Handler
  def method, do: "lang.dev.models.ingest"
  def handle(%{"id" => id}, _ctx) do
    if Application.get_env(:lang, :dev_routes) do
      case Lang.Dev.Workers.DocIngestWorker.new(%{"id" => id}, queue: :analysis) |> Oban.insert() do
        {:ok, %Oban.Job{id: jid}} -> {:ok, %{enqueued: true, job_id: jid}}
        {:error, reason} -> {:error, inspect(reason)}
      end
    else
      {:error, :dev_routes_disabled}
    end
  end
  def handle(_, _), do: {:error, :invalid_params}
end

defmodule Lang.LSP.Dev.Models.Status do
  @behaviour Lang.LSP.Handler
  import Ash.Query
  def method, do: "lang.dev.models.status"
  def handle(%{"id" => id, "status" => new_status} = params, _ctx) do
    if Application.get_env(:lang, :dev_routes) do
      case Lang.Dev.ModelRegistry |> filter(model_id == ^id) |> Ash.read() do
        {:ok, [%{status: curr, version: ver, hash: hash, path: path}]} ->
          if valid_status?(curr, new_status) do
            now = DateTime.utc_now()
            attrs = %{model_id: id, version: ver, hash: hash, path: path, status: new_status, status_changed_at: now, changed_by: Map.get(params, "changed_by")}
            case Lang.Dev.ModelRegistry.upsert(attrs) do
              {:ok, _} ->
                _ = Lang.Events.emit_dev_model_event(%{event_type: "status_updated", model_id: id, status: new_status})
                # snapshot current JSON-LD
                _ =
                  case Lang.Dev.Config.fs_adapter().preview(path, max_lines: 1_000_000) do
                    {:ok, lines} ->
                      with {:ok, map} <- Lang.Dev.JSONLDHelper.parse(Enum.join(lines, "\n")) do
                        _ = Lang.Dev.ModelState.record(%{model_id: id, version: ver, hash: hash, status: new_status, path: path, event_type: "status_updated", snapshot: map, actor: Map.get(params, "changed_by")})
                        :ok
                      else
                        _ -> :ok
                      end
                    _ -> :ok
                  end
                {:ok, %{ok: true}}
              {:error, reason} -> {:error, inspect(reason)}
            end
          else
            {:error, :invalid_status_transition}
          end
        _ -> {:error, :not_found}
      end
    else
      {:error, :dev_routes_disabled}
    end
  end
  def handle(_, _), do: {:error, :invalid_params}

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
end

defmodule Lang.LSP.Dev.Models.Drift do
  @behaviour Lang.LSP.Handler
  def method, do: "lang.dev.models.drift"
  def handle(_params, _ctx) do
    if Application.get_env(:lang, :dev_routes) do
      {:ok, %{drift: Lang.Dev.Drift.report()}}
    else
      {:error, :dev_routes_disabled}
    end
  end
end

defmodule Lang.LSP.Dev.Models.Diff do
  @behaviour Lang.LSP.Handler
  import Ash.Query
  def method, do: "lang.dev.models.diff"

  # Params:
  # - {id, entry_id} → compare entry to its previous
  # - {id, from_id, to_id} → compare two specific entries
  def handle(%{"id" => model_id} = params, _ctx) do
    if Application.get_env(:lang, :dev_routes) do
      with {:ok, states} <- Lang.Dev.ModelState |> filter(model_id == ^model_id) |> Ash.read() do
        ordered = Enum.sort_by(states, & &1.at, DateTime)
        case params do
          %{"entry_id" => eid} ->
            do_diff_prev(ordered, eid)
          %{"from_id" => from, "to_id" => to} ->
            do_diff_pair(ordered, from, to)
          _ -> {:error, :invalid_params}
        end
      else
        _ -> {:error, :not_found}
      end
    else
      {:error, :dev_routes_disabled}
    end
  end
  def handle(_, _), do: {:error, :invalid_params}

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
end
