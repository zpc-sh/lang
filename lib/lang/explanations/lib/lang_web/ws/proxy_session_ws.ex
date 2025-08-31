defmodule LangWeb.WS.ProxySessionWS do
  @behaviour :websock
  require Logger

  def init(%{id: id} = state) do
    {:ok, Map.merge(%{id: id, upstream: nil}, state)}
  end

  def handle_in({text, _opcode}, %{upstream: up} = state) when is_binary(text) do
    case decode(text) do
      %{"type" => "connect", "params" => params} ->
        case start_upstream(params, state) do
          {:ok, up2, st2} -> {:push, {:text, ~s/{"type":"connected"}/}, %{st2 | upstream: up2}}
          {:error, reason} -> {:push, {:text, encode(%{"type" => "error", "error" => inspect(reason)})}, state}
        end

      %{"type" => "stdin", "data" => data} when is_binary(data) ->
        if up, do: GenServer.cast(up, {:stdin, data})
        {:ok, state}

      _ ->
        {:ok, state}
    end
  end

  def handle_in(_other, state), do: {:ok, state}

  def handle_info({:proxy_stdout, text}, state) when is_binary(text) do
    {:push, {:text, encode(%{"type" => "stdout", "data" => text})}, state}
  end
  def handle_info({:proxy_exit, code}, state) do
    {:push, {:text, encode(%{"type" => "exit", "code" => code})}, state}
  end
  def handle_info(_msg, state), do: {:ok, state}

  def terminate(_reason, %{upstream: up} = _state) do
    if up, do: Process.exit(up, :kill)
    :ok
  end

  defp start_upstream(params, %{id: id} = state) do
    proto = Map.get(params, "proto") || Map.get(params, :proto) || "ws"
    case proto do
      "ws" ->
        url = Map.get(params, "url") || Map.get(params, :url)
        if is_binary(url) do
          case Lang.Proxy.WSUpstream.start_link(ws: self(), url: url) do
            {:ok, pid} -> {:ok, pid, state}
            other -> other
          end
        else
          {:error, :missing_url}
        end
      other -> {:error, {:unsupported_proto, other}}
    end
  end

  defp decode(text) do
    try do
      Jason.decode!(text)
    rescue
      _ -> %{}
    end
  end

  defp encode(map), do: Jason.encode!(map)
end

