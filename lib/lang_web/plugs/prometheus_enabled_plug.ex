defmodule LangWeb.Plugs.PrometheusEnabledPlug do
  @moduledoc """
  Guards metrics endpoints behind config flag.

  Enabled when Secrets.telemetry_config().prometheus_enabled == true.
  Otherwise returns 404 to avoid leaking endpoint existence.
  """
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    cfg = Lang.Security.Secrets.telemetry_config()

    if cfg.prometheus_enabled do
      conn
    else
      conn |> send_resp(404, "") |> halt()
    end
  end
end

