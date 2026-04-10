defmodule Lang.Mulsp.Instance do
  @moduledoc """
  A BEAM-mode mulsp/muyata instance managed by Lang.

  On start: loads the partition config and launches the appropriate
  application supervisor (Mulsp.Application or Muyata.Application)
  as a linked child.

  The instance process monitors the spawned app supervisor and
  deregisters from Lang.Mulsp.Registry on exit.

  For cross-node usage (mulsp running in a separate VM), this becomes
  a thin proxy that communicates via the control port instead.
  """
  use GenServer, restart: :transient

  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @impl true
  def init(opts) do
    kind = Keyword.fetch!(opts, :kind)
    node_id = Keyword.fetch!(opts, :node_id)
    config = Keyword.fetch!(opts, :config)

    # Inject config into application env before starting
    app = app_for(kind)
    Application.put_env(app, :mulsp_partition, config)
    Application.put_env(app, :mulsp_node_id, node_id)

    case Application.ensure_all_started(app) do
      {:ok, _started} ->
        Logger.info("[Lang.Mulsp.Instance] #{kind} #{node_id} started app=#{app}")
        {:ok, %{kind: kind, node_id: node_id, app: app, config: config}}

      {:error, {failed_app, reason}} ->
        Logger.error("[Lang.Mulsp.Instance] #{kind} #{node_id} failed to start #{failed_app}: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  @impl true
  def terminate(_reason, %{kind: kind, node_id: node_id, app: app}) do
    Logger.info("[Lang.Mulsp.Instance] #{kind} #{node_id} stopping, deregistering")
    Application.stop(app)
    Lang.Mulsp.Registry.deregister(node_id)
    :ok
  end

  defp app_for(:mulsp), do: :mulsp
  defp app_for(:muyata), do: :muyata
end
