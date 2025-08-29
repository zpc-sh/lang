defmodule Lang.LSP.ClientPool do
  @moduledoc """
  Round-robin pool of persistent LSP client workers for concurrent JSON-RPC.

  Configuration (config.exs):
    config :lang, :lsp_client, use_pool: true, pool_size: 3
  """

  use GenServer
  require Logger

  @default_pool_size 2

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Call LSP via one of the workers.
  """
  def call(method, params \\ %{}, opts \\ []) do
    GenServer.call(__MODULE__, {:call, method, params, opts})
  end

  @doc """
  Returns pool metrics with inflight counts per worker.
  """
  def metrics do
    GenServer.call(__MODULE__, :metrics)
  end

  @doc """
  Emits telemetry and returns current pool metrics.
  Alias of `metrics/0` for explicit intent.
  """
  def emit_metrics, do: metrics()

  @impl true
  def init(opts) do
    cfg = Application.get_env(:lang, :lsp_client) || %{}

    pool_size =
      cond do
        is_list(cfg) -> Keyword.get(cfg, :pool_size, @default_pool_size)
        is_map(cfg) -> Map.get(cfg, :pool_size, @default_pool_size)
        true -> @default_pool_size
      end

    host = Keyword.get(opts, :host, ~c"127.0.0.1")
    port = Keyword.get(opts, :port, 4001)
    root_path = Keyword.get(opts, :root_path, System.cwd!())

    workers =
      for _ <- 1..max(1, pool_size) do
        {:ok, pid} = Lang.LSP.ClientWorker.start_link(host: host, port: port, root_path: root_path)
        pid
      end

    {:ok, %{workers: workers, next: 0}}
  end

  @impl true
  def handle_call({:call, method, params, opts}, _from, %{workers: workers, next: idx} = state) do
    case workers do
      [] ->
        {:reply, {:error, :no_workers}, state}

      _ ->
        i = rem(idx, length(workers))
        pid = Enum.at(workers, i)
        reply = Lang.LSP.ClientWorker.call(pid, method, params, opts)
        {:reply, reply, %{state | next: i + 1}}
    end
  end

  @impl true
  def handle_call(:metrics, _from, %{workers: workers} = state) do
    infos =
      Enum.map(workers, fn pid ->
        case GenServer.call(pid, :metrics, 1000) do
          %{inflight: inflight, initialized: init, max_inflight: max} -> %{pid: pid, inflight: inflight, initialized: init, max_inflight: max}
          _ -> %{pid: pid, error: :no_response}
        end
      end)

    # Emit telemetry event for external observers
    :telemetry.execute([:lang, :lsp, :client, :pool, :metrics], %{}, %{workers: length(workers), details: infos})

    {:reply, %{workers: length(workers), details: infos}, state}
  end
end
