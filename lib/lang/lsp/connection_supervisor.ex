defmodule Lang.LSP.ConnectionSupervisor do
  @moduledoc """
  Supervises the pool of connection workers that handle individual client sockets.
  """
  use DynamicSupervisor

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def start_worker(socket) do
    spec = {Lang.LSP.ConnectionWorker, socket}
    DynamicSupervisor.start_child(__MODULE__, spec)
  end
end
