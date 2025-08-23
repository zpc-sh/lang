defmodule Lang.LSP.Supervisor do
  @moduledoc """
  Supervisor for the Language Server Protocol implementation.
  Manages the LSP server and related processes.
  """
  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    children = [
      # LSP Server
      {Lang.LSP.Server, port: lsp_port()},

      # Connection pool for handling multiple LSP clients
      {Registry, keys: :unique, name: Lang.LSP.Registry},

      # Task supervisor for async operations
      {Task.Supervisor, name: Lang.LSP.TaskSupervisor}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp lsp_port do
    Application.get_env(:lang, :lsp_port, 4001)
  end
end
