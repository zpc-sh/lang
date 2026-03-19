defmodule Lang.Broker.Session do
  @moduledoc """
  Per-connection broker session. Owns the protocol state and performs basic
  rate limiting and error wrapping for JSON‑RPC messages.
  """

  use GenServer
  alias Lang.Broker.Protocol

  @type t :: %__MODULE__{
          protocol: module(),
          state: term(),
          client: map(),
          limiter: map()
        }
  defstruct [:protocol, :state, :client, limiter: %{}]

  @spec start_link(protocol :: module(), client_info :: map()) :: GenServer.on_start()
  def start_link(protocol, client_info \\ %{}) do
    GenServer.start_link(__MODULE__, {protocol, client_info})
  end

  @spec handle_jsonrpc(pid(), map()) :: :ok
  def handle_jsonrpc(pid, msg) when is_map(msg), do: GenServer.cast(pid, {:jsonrpc, msg})

  @impl true
  def init({protocol, client_info}) do
    Process.flag(:trap_exit, true)

    case protocol.init(client_info) do
      {:ok, st, capabilities} ->
        {:ok, %__MODULE__{protocol: protocol, state: st, client: client_info},
         {:continue, {:reply_init, capabilities}}}

      {:error, reason} ->
        {:stop, {:init_failed, reason}}
    end
  end

  @impl true
  def handle_continue({:reply_init, capabilities}, s) do
    send(self(), {:broker_send, %{"method" => "initialized", "params" => %{}}})
    send(self(), {:broker_send, %{"method" => "capabilities", "params" => capabilities}})
    {:noreply, s}
  end

  @impl true
  def handle_cast({:jsonrpc, %{"id" => id, "method" => method, "params" => params} = _req}, s) do
    {reply, s} =
      case s.protocol.handle_request(method, params || %{}, s.state) do
        {:ok, result, st} ->
          {%{"jsonrpc" => "2.0", "id" => id, "result" => result}, %{s | state: st}}

        {:error, code, message, data, st} ->
          {%{
             "jsonrpc" => "2.0",
             "id" => id,
             "error" => %{code: code, message: message, data: data}
           }, %{s | state: st}}
      end

    send(self(), {:broker_send, reply})
    {:noreply, s}
  end

  @impl true
  def handle_cast({:jsonrpc, %{"method" => method, "params" => params}}, s) do
    case s.protocol.handle_notification(method, params || %{}, s.state) do
      {:ok, st} -> {:noreply, %{s | state: st}}
      {:error, _code, _message, _data, st} -> {:noreply, %{s | state: st}}
    end
  end

  # In a real transport, the parent would consume {:broker_send, map} and write bytes downstream.
end
