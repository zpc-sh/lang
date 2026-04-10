defmodule Muyata.Application do
  @moduledoc """
  muyata supervisor tree. Crash-resilient — any child dies, it restarts.

  Children are started based on the void config. The conduit, observer,
  and substrate always start. Protocol surfaces are conditional.
  """
  use Application

  @impl true
  def start(_type, _args) do
    void_opts = load_config()

    children =
      [
        # The void state — always
        {Muyata.Void, void_opts},
        # Observer pipeline — always
        Muyata.Observer.Tap,
        Muyata.Observer.Framing,
        Muyata.Observer.Census,
        Muyata.Observer.Heatmap,
        # Substrate — always
        Muyata.Substrate.Tree,
        Muyata.Substrate.Bloom,
        Muyata.Substrate.Epoch,
        # The conduit — always
        {Muyata.Conduit.Listener, void_opts},
        # Protocol surfaces — conditional
        gopher_enabled?(void_opts) &&
          {Muyata.Gopher.Server, port: Keyword.get(void_opts, :gopher_port, 7170)},
        finger_enabled?(void_opts) &&
          {Muyata.Finger.Server, port: Keyword.get(void_opts, :finger_port, 7179)},
        dc_enabled?(void_opts) &&
          {Muyata.DC.Peer, port: Keyword.get(void_opts, :dc_port, 7171)},
        # Mesh clustering
        {Muyata.Mesh.Cluster, void_opts}
      ]
      |> Enum.filter(&(&1 != false))

    opts = [strategy: :one_for_one, name: Muyata.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp load_config do
    [
      listen_port: env_int("MUYATA_LISTEN_PORT", 5432),
      upstream_host: System.get_env("MUYATA_UPSTREAM_HOST") || "127.0.0.1",
      upstream_port: env_int("MUYATA_UPSTREAM_PORT", 5433),
      gopher_port: env_int("MUYATA_GOPHER_PORT", 7170),
      finger_port: env_int("MUYATA_FINGER_PORT", 7179),
      dc_port: env_int("MUYATA_DC_PORT", 7171)
    ]
  end

  defp env_int(var, default) do
    case System.get_env(var) do
      nil -> default
      val -> String.to_integer(val)
    end
  end

  defp gopher_enabled?(opts), do: Keyword.get(opts, :gopher_enabled, true)
  defp finger_enabled?(opts), do: Keyword.get(opts, :finger_enabled, true)
  defp dc_enabled?(opts), do: Keyword.get(opts, :dc_enabled, true)
end
