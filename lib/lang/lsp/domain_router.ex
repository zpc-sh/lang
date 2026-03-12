defmodule Lang.LSP.DomainRouter do
  @moduledoc """
  Routes `lang.*` methods to the appropriate Domain Broker.

  Initial scope: filesystem methods routed to `Lang.LSP.Brokers.FS`.
  """

  alias Lang.LSP.{Configuration}

  @type jsonrpc_request :: map()

  @doc """
  Handle a JSON-RPC request via the appropriate broker and return a full JSON-RPC response map.
  """
  @spec handle(jsonrpc_request) :: map()
  def handle(%{"id" => id, "method" => method} = req) when is_binary(method) do
    config = Configuration.from_request(req)

    case route(method) do
      {:ok, broker} ->
        to_jsonrpc(id, broker.handle(req, config))

      :unknown ->
        error(id, -32601, "Method not found", %{method: method})
    end
  end

  def handle(%{"id" => id} = _req), do: error(id, -32600, "Invalid request")
  def handle(_), do: %{}

  # -------------------------------------------------------------------------
  # Routing
  # -------------------------------------------------------------------------
  defp route("lang.fs." <> _), do: {:ok, Lang.LSP.Brokers.FS}
  defp route("lang.parser." <> _), do: {:ok, Lang.LSP.Brokers.Parser}
  defp route("lang.workspace." <> _), do: {:ok, Lang.LSP.Brokers.Workspace}
  defp route(_), do: :unknown

  # -------------------------------------------------------------------------
  # Helpers
  # -------------------------------------------------------------------------
  defp to_jsonrpc(id, {:ok, result}), do: %{"jsonrpc" => "2.0", "id" => id, "result" => result}

  defp to_jsonrpc(id, {:error, code, message}) when is_integer(code) and is_binary(message) do
    %{"jsonrpc" => "2.0", "id" => id, "error" => %{"code" => code, "message" => message}}
  end

  defp to_jsonrpc(id, {:error, code, message, data}) do
    %{"jsonrpc" => "2.0", "id" => id, "error" => %{"code" => code, "message" => message, "data" => data}}
  end

  defp error(id, code, message, data \\ %{}) do
    to_jsonrpc(id, {:error, code, message, data})
  end
end
