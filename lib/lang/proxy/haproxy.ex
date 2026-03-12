defmodule Lang.Proxy.HAProxy do
  @moduledoc """
  High-level HAProxy integration helpers: schedule reconciliation and expose
  minimal health checks for admin surfaces.
  """

  @doc """
  Schedule a reconciliation pass with optional backend/servers override.
  """
  def reconcile_async(overrides \\ %{}) when is_map(overrides) do
    overrides
    |> Lang.Workers.HAProxyReconcilerWorker.new(queue: :metrics)
    |> Oban.insert()
  end

  @doc """
  Return configured base_url and whether auth is present, for quick UI health.
  """
  def config_info do
    cfg = Application.get_env(:lang, :haproxy, %{})
    auth = cfg[:auth]
    auth_configured? =
      case auth do
        {:basic, {_u, _p}} -> true
        {:bearer, _token} -> true
        _ -> false
      end

    %{
      base_url: cfg[:base_url],
      auth_configured?: auth_configured?
    }
  end
end
