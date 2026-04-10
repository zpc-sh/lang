defmodule Mulsp.Application do
  @moduledoc """
  mulsp supervisor tree. Crash-resilient — any child dies, it restarts.
  The whole point is we don't care about individual crashes.

  Children are started based on the partition config — a security
  specialist mulsp won't start the LSP handlers, a code reviewer
  won't start the DC hub.
  """
  use Application

  @impl true
  def start(_type, _args) do
    partition = Mulsp.Partition.load()

    children =
      [
        # Always start: dispatch is the brain
        {Mulsp.Dispatch, partition: partition},
        # Always start: gopher is how we're found
        {Mulsp.Gopher.Server, port: partition.gopher_port},
        # Finger for .plan status
        partition.finger_enabled && {Mulsp.Finger.Server, port: partition.finger_port},
        # DC hub for sparse tree transfers
        partition.dc_enabled && {Mulsp.DC.Hub, port: partition.dc_port},
        # Mesh clustering
        {Mulsp.Mesh.Cluster, partition: partition},
        # LSP transport (stdio or TCP based on config)
        partition.lsp_enabled && {Mulsp.Transport.Tcp, port: partition.lsp_port},
        # Control channel — Lang pushes partition updates here
        {Mulsp.Control, port: partition.control_port}
      ]
      |> Enum.filter(&(&1 != false))

    opts = [strategy: :one_for_one, name: Mulsp.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
