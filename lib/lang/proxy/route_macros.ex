defmodule Lang.Proxy.RouteMacros do
  @moduledoc "Helper macros for building common proxy routes"

  @doc """
  Build a bootstrap→verify→ingest route for a workspace.

  opts:
  - host, user, cmd (for ssh bootstrap)
  - file_path (for verify symbols)
  - workspace_id, root (for ingest all symbols)
  - intent: optional pre-signed token; if absent and required, caller should attach later
  """
  def bootstrap_verify_ingest(opts) do
    host = opts[:host]
    user = opts[:user]
    cmd = opts[:cmd]
    file_path = opts[:file_path]
    workspace_id = opts[:workspace_id]
    root = opts[:root]
    intent = opts[:intent]

    hops = [
      %{
        service: "lsp",
        method: "lsp.bootstrap_ssh",
        params: filter_nil(%{"host" => host, "user" => user, "cmd" => cmd, "intent" => intent}),
        timeout_ms: 8_000,
        retries: 1,
        backoff_ms: 500
      }
    ]

    hops =
      if file_path do
        hops ++ [%{service: "lsp", method: "lsp.symbols", params: %{"file_path" => file_path}}]
      else
        hops
      end

    hops =
      if workspace_id && root do
        hops ++ [%{service: "lsp", method: "lsp.symbols", params: %{"file_path" => root}}]
      else
        hops
      end

    hops
  end

  defp filter_nil(m) do
    m |> Enum.reject(fn {_k, v} -> is_nil(v) end) |> Enum.into(%{})
  end
end

