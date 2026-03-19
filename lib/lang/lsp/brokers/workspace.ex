defmodule Lang.LSP.Brokers.Workspace do
  @moduledoc """
  Workspace broker: schedules snapshot/reduction jobs, resolves roots.
  """

  @behaviour Lang.LSP.DomainBroker
  alias Lang.LSP.Configuration
  alias Lang.Workspace.Resolver

  @impl true
  def init(_cfg), do: {:ok, :ready}

  @impl true
  def handle(%{"method" => "lang.workspace.snapshot", "id" => _id, "params" => params} = _req,
        %Configuration{} = cfg) do
    ctx = %{
      workspace_root: cfg.workspace_root || params["workspace_root"],
      workspace_id: params["workspace_id"],
      repository: cfg.repository || params["repository"]
    }

    with {:ok, root} <- Resolver.resolve_root(ctx),
         {:ok, job} <- enqueue_snapshot(root, cfg, params) do
      {:ok, %{job_id: job.id}}
    else
      {:error, {:billing_blocked, _}=_e} -> {:error, -32001, "billing_blocked"}
      {:error, :workspace_unresolved} -> {:error, -32602, "workspace_unresolved"}
      {:error, other} -> {:error, -32002, to_string(other)}
    end
  end

  def handle(_req, _cfg), do: {:error, -32601, "Method not found"}

  @impl true
  def terminate(_state), do: :ok

  defp enqueue_snapshot(root, cfg, params) do
    args = %{
      "workspace_root" => root,
      "repository" => cfg.repository || params["repository"],
      "org_id" => cfg.org_id,
      "max_depth" => params["max_depth"] || 12,
      "reduce" => params["reduce"] || "manifest_only",
      "max_files" => params["max_files"] || 5_000,
      "include_globs" => params["include_globs"] || [],
      "exclude_globs" => params["exclude_globs"] || [],
      "key" => params["key"]
    }

    job = Lang.Workers.WorkspaceSnapshotWorker.new(args, queue: :analysis, priority: 2)
    case Oban.insert(job) do
      {:ok, job} -> {:ok, job}
      other -> other
    end
  end
end
