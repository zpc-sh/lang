defmodule Lang.Mulsp.InstanceSupervisor do
  @moduledoc """
  DynamicSupervisor for live mulsp/muyata BEAM instances.
  Each spawned instance is a supervised child — crash → restart → re-register.
  """
  use DynamicSupervisor

  def start_link(opts \\ []) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
