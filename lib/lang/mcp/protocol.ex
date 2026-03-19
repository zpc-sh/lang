defmodule Lang.MCP.Protocol do
  @moduledoc """
  Minimal MCP protocol implementation for the generic broker.

  Implements a small subset:
  - initialize (returns capabilities + grouped tools)
  - listTools (returns grouped tools)
  - callTool (maps to LSP via ToolRegistry)
  - notifications are ignored (ACK)
  """

  @behaviour Lang.Broker.Protocol
  alias Lang.MCP.ToolRegistry

  @impl true
  def name, do: "mcp"

  @impl true
  def init(params) do
    caps = %{
      "protocol" => "mcp/0.1",
      "tools" => ToolRegistry.grouped()
    }

    {:ok, %{client: params}, caps}
  end

  @impl true
  def handle_request("listTools", _params, s) do
    {:ok, %{tools: ToolRegistry.grouped()}, s}
  end

  def handle_request("callTool", %{"name" => name} = params, s) do
    args = Map.get(params, "arguments", %{})

    case ToolRegistry.get(name) do
      {:ok, %{lsp_method: method, map_args: mapper}} ->
        lsp_params = if is_function(mapper, 1), do: mapper.(args), else: args

        # Build an LSP-like request for Dispatch; use a synthetic id (broker wraps result)
        req = %{"jsonrpc" => "2.0", "id" => 1, "method" => method, "params" => lsp_params}

        case Lang.LSP.Dispatch.process(req) do
          %{"result" => result} -> {:ok, %{content: result}, s}
          %{"error" => err} -> {:error, -32000, "tool_error", err, s}
          nil -> {:error, -32601, "method not found", %{method: method}, s}
        end

      :error ->
        {:error, -32601, "tool not found", %{name: name}, s}
    end
  end

  def handle_request(_method, _params, s) do
    {:error, -32601, "method not found", %{}, s}
  end

  @impl true
  def handle_notification(_method, _params, s) do
    {:ok, s}
  end

  @impl true
  def tools(_s) do
    ToolRegistry.grouped()
  end
end
