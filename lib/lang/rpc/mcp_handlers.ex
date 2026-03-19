defmodule Lang.RPC.MCPHandlers do
  @moduledoc false
  require Logger

  def connection_create(ctx, params) do
    org_id = get_in(ctx, [:organization, :id])
    conn_id = "mcp_conn_" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
    if org_id, do: Lang.Billing.Service.report_mcp_connection(org_id)

    {:ok,
     %{connection_id: conn_id, status: "connecting", session_id: Map.get(params, "session_id")}}
  end

  def connection_status(_ctx, %{"connection_id" => conn_id}) do
    {:ok, %{connection_id: conn_id, status: "connected"}}
  end

  def connection_destroy(ctx, %{"connection_id" => conn_id}) do
    org_id = get_in(ctx, [:organization, :id])
    track_event(org_id, "mcp_connection_destroyed", %{connection_id: conn_id})
    {:ok, %{ok: true, connection_id: conn_id}}
  end

  defp track_event(nil, _type, _meta), do: :ok

  defp track_event(org_id, type, meta) do
    try do
      Lang.Events.track_event(%{event_type: type, organization_id: org_id, metadata: meta})
    rescue
      _ -> :ok
    end
  end
end
