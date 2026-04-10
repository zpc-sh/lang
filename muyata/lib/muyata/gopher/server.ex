defmodule Muyata.Gopher.Server do
  @moduledoc """
  RFC 1436 Gopher server for browsing muyata's learned knowledge.

  Browse what the void has learned: framing hypotheses, classified
  message types, heatmap coverage, sealed epochs. Any AI or human
  with `curl gopher://` gets instant structured browsing.

  Same pattern as Mulsp.Gopher.Server — 80 lines of gen_tcp.
  """
  use GenServer

  require Logger

  def start_link(opts) do
    port = Keyword.get(opts, :port, 7170)
    GenServer.start_link(__MODULE__, %{port: port}, name: __MODULE__)
  end

  @impl true
  def init(%{port: port}) do
    host = hostname()

    case :gen_tcp.listen(port, [
           :binary,
           {:active, false},
           {:reuseaddr, true},
           {:packet, :line}
         ]) do
      {:ok, listen_socket} ->
        spawn_link(fn -> accept_loop(listen_socket, host, port) end)
        Logger.info("[muyata:gopher] listening on port #{port}")
        {:ok, %{listen_socket: listen_socket, port: port, host: host}}

      {:error, reason} ->
        Logger.warning("[muyata:gopher] failed to bind port #{port}: #{inspect(reason)}")
        {:ok, %{port: port, host: host}}
    end
  end

  @impl true
  def terminate(_reason, %{listen_socket: socket}) when not is_nil(socket) do
    :gen_tcp.close(socket)
  end

  def terminate(_reason, _state), do: :ok

  defp accept_loop(listen_socket, host, port) do
    case :gen_tcp.accept(listen_socket) do
      {:ok, client} ->
        spawn(fn -> handle_client(client, host, port) end)
        accept_loop(listen_socket, host, port)

      {:error, :closed} ->
        :ok

      {:error, reason} ->
        Logger.warning("[muyata:gopher] accept error: #{inspect(reason)}")
        accept_loop(listen_socket, host, port)
    end
  end

  defp handle_client(socket, host, port) do
    case :gen_tcp.recv(socket, 0, 5_000) do
      {:ok, data} ->
        selector = String.trim(data)
        response = Muyata.Gopher.Handler.handle(selector, host, port)
        :gen_tcp.send(socket, response)
        :gen_tcp.close(socket)

      {:error, _} ->
        :gen_tcp.close(socket)
    end
  end

  defp hostname do
    case :inet.gethostname() do
      {:ok, name} -> to_string(name)
      _ -> "localhost"
    end
  end

  # --- Gopher item formatters ---

  def info(text), do: "i#{text}\tfake\t(NULL)\t0\r\n"
  def dir(display, selector, host, port), do: "1#{display}\t#{selector}\t#{host}\t#{port}\r\n"
  def text(display, selector, host, port), do: "0#{display}\t#{selector}\t#{host}\t#{port}\r\n"
  def error(message), do: "3#{message}\tfake\t(NULL)\t0\r\n"
  def terminator, do: ".\r\n"
end
