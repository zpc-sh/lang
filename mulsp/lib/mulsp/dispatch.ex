defmodule Mulsp.Dispatch do
  @moduledoc """
  Central dispatch — the anti-2830-line-case-statement.

  Registry of handlers with route actions. Methods are routed based
  on the partition config: handle locally, proxy to a specific peer,
  broadcast to mesh, forward to full Lang, or drop.

  This GenServer is the brain. Everything flows through it.
  """
  use GenServer

  defmodule State do
    @moduledoc false
    defstruct [
      :partition,
      handlers: %{},
      peers: %{}
    ]
  end

  # --- Client API ---

  def start_link(opts) do
    partition = Keyword.fetch!(opts, :partition)
    GenServer.start_link(__MODULE__, partition, name: __MODULE__)
  end

  @doc """
  Dispatch a request. Returns {:ok, response} or {:error, reason}.
  """
  def dispatch(method, params \\ nil, id \\ nil) do
    GenServer.call(__MODULE__, {:dispatch, method, params, id})
  end

  @doc """
  Register a local handler module for a method.
  """
  def register_handler(method, handler_mod) do
    GenServer.cast(__MODULE__, {:register, method, handler_mod})
  end

  @doc """
  Update partition config at runtime (e.g., pushed by Lang SaaS).
  """
  def update_partition(partition) do
    GenServer.cast(__MODULE__, {:update_partition, partition})
  end

  # --- Server ---

  @impl true
  def init(partition) do
    state = %State{partition: partition, handlers: %{}, peers: %{}}

    # Register built-in handlers
    state = register_builtins(state)

    {:ok, state}
  end

  @impl true
  def handle_call({:dispatch, method, params, id}, _from, state) do
    request = %{method: method, params: params, id: id}

    {action, state} = route(method, state)

    result =
      case action do
        :local ->
          handle_local(method, request, state)

        {:proxy, target} ->
          handle_proxy(target, request, state)

        :mesh ->
          handle_mesh(request, state)

        :lang ->
          handle_lang(request, state)

        :drop ->
          {:error, :method_not_found, "#{method} not in partition"}
      end

    {:reply, result, state}
  end

  @impl true
  def handle_cast({:register, method, handler_mod}, state) do
    {:noreply, %{state | handlers: Map.put(state.handlers, method, handler_mod)}}
  end

  def handle_cast({:update_partition, partition}, state) do
    {:noreply, %{state | partition: partition}}
  end

  # --- Routing ---

  defp route(method, state) do
    cond do
      # Exact local handler registered
      Map.has_key?(state.handlers, method) ->
        {:local, state}

      # In local_methods list
      method in state.partition.local_methods ->
        {:local, state}

      # Exact proxy rule
      Map.has_key?(state.partition.proxy_methods, method) ->
        {{:proxy, Map.get(state.partition.proxy_methods, method)}, state}

      # Wildcard mesh match
      matches_wildcard?(method, state.partition.mesh_methods) ->
        {:mesh, state}

      # Wildcard lang match
      matches_wildcard?(method, state.partition.lang_methods) ->
        {:lang, state}

      # Nothing matches
      true ->
        {:drop, state}
    end
  end

  defp matches_wildcard?(method, patterns) do
    Enum.any?(patterns, fn pattern ->
      if String.ends_with?(pattern, "*") do
        prefix = String.trim_trailing(pattern, "*")
        String.starts_with?(method, prefix)
      else
        method == pattern
      end
    end)
  end

  defp handle_local(method, request, state) do
    case Map.get(state.handlers, method) do
      nil ->
        {:error, :no_handler, "#{method} routed local but no handler"}

      handler_mod ->
        try do
          handler_mod.handle(request)
        rescue
          e -> {:error, :internal, Exception.message(e)}
        end
    end
  end

  defp handle_proxy(target, request, _state) do
    # Forward to specific peer via DC or TCP
    case Mulsp.Mesh.Cluster.forward(target, request) do
      {:ok, response} -> {:ok, response}
      {:error, reason} -> {:error, :proxy_failed, reason}
    end
  end

  defp handle_mesh(request, _state) do
    # Broadcast to mesh, first responder wins
    case Mulsp.Mesh.Cluster.broadcast(request) do
      {:ok, response} -> {:ok, response}
      {:error, reason} -> {:error, :mesh_failed, reason}
    end
  end

  defp handle_lang(request, _state) do
    # Forward to full Lang platform
    Mulsp.Bridge.Lang.forward(request)
  end

  defp register_builtins(state) do
    handlers = %{
      "initialize" => Mulsp.LSP.Lifecycle,
      "initialized" => Mulsp.LSP.Lifecycle,
      "shutdown" => Mulsp.LSP.Lifecycle,
      "exit" => Mulsp.LSP.Lifecycle,
      "textDocument/didOpen" => Mulsp.LSP.TextSync,
      "textDocument/didChange" => Mulsp.LSP.TextSync,
      "textDocument/didClose" => Mulsp.LSP.TextSync
    }

    %{state | handlers: Map.merge(state.handlers, handlers)}
  end
end
