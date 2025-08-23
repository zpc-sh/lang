defmodule LangWeb.LSPSocket do
  @moduledoc """
  Phoenix Socket for Language Server Protocol connections.
  Provides WebSocket-based LSP communication with streaming support.
  """
  use Phoenix.Socket

  channel "lsp:*", LangWeb.LSPChannel

  @impl true
  def connect(_params, socket, _connect_info) do
    {:ok, socket}
  end

  @impl true
  def id(_socket), do: nil
end
