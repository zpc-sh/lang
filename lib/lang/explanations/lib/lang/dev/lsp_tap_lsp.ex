defmodule Lang.LSP.Dev.Lsp.TapStart do
  @behaviour Lang.LSP.Handler
  def method, do: "lang.dev.lsp.tap_start"
  def handle(%{"client_id" => cid} = params, _ctx) do
    if Application.get_env(:lang, :dev_routes) do
      attrs = %{
        "active" => true,
        "methods" => (params["methods"] and Enum.join(List.wrap(params["methods"]), ",")) || "",
        "max" => params["max"] || 500
      }
      Lang.Dev.LSPTracer.configure(cid, attrs)
    else
      {:error, :dev_routes_disabled}
    end
  end
  def handle(_, _), do: {:error, :invalid_params}
end

defmodule Lang.LSP.Dev.Lsp.TapStop do
  @behaviour Lang.LSP.Handler
  def method, do: "lang.dev.lsp.tap_stop"
  def handle(%{"client_id" => cid}, _ctx) do
    if Application.get_env(:lang, :dev_routes) do
      Lang.Dev.LSPTracer.configure(cid, %{"active" => false})
    else
      {:error, :dev_routes_disabled}
    end
  end
  def handle(_, _), do: {:error, :invalid_params}
end

defmodule Lang.LSP.Dev.Lsp.Trace do
  @behaviour Lang.LSP.Handler
  def method, do: "lang.dev.lsp.trace"
  def handle(%{"client_id" => cid} = params, _ctx) do
    if Application.get_env(:lang, :dev_routes) do
      limit = params["limit"] || 200
      method = params["method"]
      since = params["since"]
      Lang.Dev.LSPTracer.list_traces(cid, %{limit: limit, method: method, since: since})
    else
      {:error, :dev_routes_disabled}
    end
  end
  def handle(_, _), do: {:error, :invalid_params}
end
