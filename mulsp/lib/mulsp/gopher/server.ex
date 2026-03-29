defmodule Mulsp.Gopher.Server do
  @moduledoc """
  RFC 1436 Gopher server. THE PROMISE.

  Serves a menu hierarchy of mulsp capabilities on port 70 (or configured).
  Any AI — or human with `curl gopher://` — gets instant structured browsing
  of what this mulsp node can do.

  Gopher is perfect for this:
  - Machine-parseable (type char + display string + selector + host + port)
  - No HTTP overhead, no TLS negotiation, no headers
  - Menu-driven = natural for capability browsing
  - Modern scanners don't watch port 70
  - Runs on `gen_tcp` — native AtomVM support

  Protocol:
  1. Client connects, sends selector + CRLF
  2. Server responds with content
  3. Connection closes

  That's it. No keep-alive, no content-length, no chunked encoding.
  """
  use GenServer

  require Logger

  defmodule State do
    @moduledoc false
    defstruct [:listen_socket, :port, :host]
  end

  # Gopher item types
  @text_file "0"
  @directory "1"
  @info "i"
  @error "3"

  def start_link(opts) do
    port = Keyword.get(opts, :port, 7070)
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
        # Accept connections in a separate process
        spawn_link(fn -> accept_loop(listen_socket, host, port) end)

        Logger.info("[mulsp:gopher] listening on port #{port}")
        {:ok, %State{listen_socket: listen_socket, port: port, host: host}}

      {:error, reason} ->
        Logger.warning("[mulsp:gopher] failed to bind port #{port}: #{inspect(reason)}")
        # Don't crash the supervisor — just start without gopher
        {:ok, %State{port: port, host: host}}
    end
  end

  @impl true
  def terminate(_reason, %{listen_socket: socket}) when not is_nil(socket) do
    :gen_tcp.close(socket)
  end

  def terminate(_reason, _state), do: :ok

  # --- Accept Loop ---

  defp accept_loop(listen_socket, host, port) do
    case :gen_tcp.accept(listen_socket) do
      {:ok, client} ->
        spawn(fn -> handle_client(client, host, port) end)
        accept_loop(listen_socket, host, port)

      {:error, :closed} ->
        :ok

      {:error, reason} ->
        Logger.warning("[mulsp:gopher] accept error: #{inspect(reason)}")
        accept_loop(listen_socket, host, port)
    end
  end

  defp handle_client(socket, host, port) do
    case :gen_tcp.recv(socket, 0, 5_000) do
      {:ok, data} ->
        selector = data |> String.trim()
        response = Mulsp.Gopher.Handler.handle(selector, host, port)
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

  # --- Public API for building gopher items ---

  @doc "Format a gopher menu item: type, display, selector, host, port"
  def item(type, display, selector, host, port) do
    "#{type}#{display}\t#{selector}\t#{host}\t#{port}\r\n"
  end

  @doc "Format an informational line (type i)"
  def info(text), do: "#{@info}#{text}\tfake\t(NULL)\t0\r\n"

  @doc "Format a directory link (type 1)"
  def dir(display, selector, host, port) do
    item(@directory, display, selector, host, port)
  end

  @doc "Format a text file link (type 0)"
  def text(display, selector, host, port) do
    item(@text_file, display, selector, host, port)
  end

  @doc "Format an error line (type 3)"
  def error(message), do: "#{@error}#{message}\tfake\t(NULL)\t0\r\n"

  @doc "Gopher menu terminator"
  def terminator, do: ".\r\n"
end
