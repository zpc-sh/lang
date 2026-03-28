defmodule Lang.Guard.Supervisor do
  @moduledoc """
  OTP supervisor for the Guard Mesh integration layer.

  Manages the local scanner, washer, coglet store, mesh client,
  finger bridge, gopher server, spillover routing, federation,
  and telemetry processes that connect this LANG instance to the
  public Guard Mesh network.
  """

  use Supervisor

  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
      {Lang.Guard.CogletStore, []},
      {Lang.Guard.Scanner, []},
      {Lang.Guard.Washer, []},
      {Lang.Guard.Stigmergy, []},
      {Lang.Guard.Purifier, []},
      {Lang.Guard.Spillover, []},
      {Lang.Guard.MeshClient, []},
      {Lang.Guard.FingerBridge, []},
      {Lang.Guard.Gopher, []},
      {Lang.Guard.Federation, []},
      {Lang.Guard.Telemetry, []}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
