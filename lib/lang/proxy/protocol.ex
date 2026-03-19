defmodule Lang.Proxy.Protocol do
  @moduledoc """
  Primary Proxy Protocol for the broker. Reusable envelope across services.

  JSON-RPC Methods:
  - "proxy.call": {v, service, method, params, opts, meta} -> result
  - "proxy.capabilities": returns supported services and version
  - "proxy.health": quick health check for proxy layer
  """

  @behaviour Lang.Broker.Protocol
  alias Lang.Proxy.{Envelope, Router}

  @impl true
  def name, do: "proxy"

  @impl true
  def init(_params) do
    caps = %{
      version: 1,
      services: [:ai],
      features: [:stream_optional, :timeouts, :provider_hint]
    }

    {:ok, %{}, caps}
  end

  @impl true
  def handle_request("proxy.capabilities", _params, state) do
    {:ok,
     %{
       version: 1,
       services: [:ai],
       features: [:stream_optional, :timeouts, :provider_hint]
     }, state}
  end

  def handle_request("proxy.health", _params, state) do
    {:ok, %{status: :ok, time: DateTime.utc_now()}, state}
  end

  def handle_request("proxy.call", params, state) when is_map(params) do
    case Envelope.new(params) do
      {:ok, env} ->
        case Router.dispatch(env) do
          {:ok, result} -> {:ok, %{result: result}, state}
          {:error, code, message, data} -> {:error, code, message, data, state}
        end

      {:error, reason} -> {:error, -32602, "Invalid params", %{reason: inspect(reason)}, state}
    end
  end

  def handle_request(_method, _params, state) do
    {:error, -32601, "Method not found", %{}, state}
  end

  @impl true
  def handle_notification("proxy.notify", params, state) when is_map(params) do
    # For now, treat like call but ignore result
    _ = handle_request("proxy.call", params, state)
    {:ok, state}
  end

  def handle_notification(_method, _params, state), do: {:ok, state}

  @impl true
  def tools(_state), do: []
end

