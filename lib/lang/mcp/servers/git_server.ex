defmodule Lang.MCP.Servers.GitServer do
  @moduledoc """
  Minimal Git MCP server stub to satisfy supervision and pooling.

  This server provides a safe, no‑op implementation that can be expanded later.
  It implements the MCP server contract used by `Lang.MCP.Pool`:
  - start_link/1 for DynamicSupervisor
  - handle_call(:health_check, ...)
  - handle_call({:mcp_request, map()}, ...)
  - handle_cast(:shutdown, ...)

  All Git operations are intentionally stubbed to avoid performing network or
  filesystem side‑effects. Requests return informative errors until a full
  implementation is added.
  """

  use GenServer
  require Logger

  # Server state
  defstruct [
    :config,
    :created_at,
    :last_request_at,
    stats: %{
      requests_handled: 0,
      errors_encountered: 0
    }
  ]

  @type server_state :: %__MODULE__{
          config: map(),
          created_at: DateTime.t(),
          last_request_at: DateTime.t() | nil,
          stats: %{requests_handled: non_neg_integer(), errors_encountered: non_neg_integer()}
        }

  ## Public API

  def start_link(config \\ %{}) do
    GenServer.start_link(__MODULE__, config)
  end

  def stop(pid), do: GenServer.stop(pid, :normal)

  ## GenServer callbacks

  @impl true
  def init(config) do
    Logger.debug("Starting Git MCP server (stub)", config: config)

    state = %__MODULE__{
      config: Map.take(config || %{}, ["repository_url", "branch", "auth"]),
      created_at: DateTime.utc_now(),
      last_request_at: nil,
      stats: %{requests_handled: 0, errors_encountered: 0}
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:health_check, _from, state) do
    details = %{
      status: :healthy,
      uptime_seconds: DateTime.diff(DateTime.utc_now(), state.created_at),
      requests_handled: state.stats.requests_handled,
      implementation: :stub,
      capabilities: ["git/info", "git/health"],
      configured_repo?: is_binary(state.config["repository_url"]) and state.config["repository_url"] != ""
    }

    {:reply, {:ok, details}, state}
  end

  @impl true
  def handle_call({:mcp_request, request}, _from, state) when is_map(request) do
    Logger.debug("Git server received request (stub)", request: request)

    state = %{state | last_request_at: DateTime.utc_now(), stats: %{state.stats | requests_handled: state.stats.requests_handled + 1}}

    case request do
      %{"method" => "git/health"} ->
        {:reply, {:ok, %{result: %{status: "ok"}}}, state}

      %{"method" => "git/info"} ->
        info = %{
          repository_url: state.config["repository_url"],
          branch: state.config["branch"] || "main",
          implementation: "stub"
        }
        {:reply, {:ok, %{result: info}}, state}

      %{"method" => method} ->
        Logger.warning("Unsupported git method (stub)", method: method)
        error_state = %{state | stats: %{state.stats | errors_encountered: state.stats.errors_encountered + 1}}
        {:reply, {:error, "Unsupported method: #{method}"}, error_state}
    end
  end

  @impl true
  def handle_cast(:shutdown, state) do
    Logger.info("Git MCP server shutting down (stub)")
    {:stop, :normal, state}
  end

  @impl true
  def terminate(reason, _state) do
    Logger.debug("Git MCP server terminated (stub)", reason: reason)
    :ok
  end
end

