defmodule LangWeb.Api.V2.LspController do
  use LangWeb, :controller
  alias LangWeb.AuthHelpers

  # POST /api/v2/lsp/connect
  # Auth: Bearer/API key via pipelines
  def connect(conn, _params) do
    user = AuthHelpers.current_user(conn)
    org = AuthHelpers.current_org(conn)

    with {:ok, :allowed} <- allow_billing(org),
         {:ok, ticket, ttl, cid} <- mint_lsp_ticket(user, org) do
      wss_url = "/ws/lsp?ticket=" <> URI.encode(ticket)
      json(conn, %{wss_url: wss_url, ticket: ticket, ttl: ttl, cid: cid})
    else
      {:error, :limit_exceeded} -> conn |> put_status(429) |> json(%{error: "rate_limited"})
      {:error, reason} -> conn |> put_status(401) |> json(%{error: to_string(reason)})
      _ -> conn |> put_status(401) |> json(%{error: "unauthorized"})
    end
  end

  # POST /api/v2/lsp/preflight
  def preflight(conn, _params) do
    user = AuthHelpers.current_user(conn)
    org = AuthHelpers.current_org(conn)

    auth_ok = user != nil and org != nil
    bill_ok = case allow_billing(org) do {:ok, :allowed} -> true; _ -> false end

    json(conn, %{
      auth_ok: auth_ok,
      billing_ok: bill_ok,
      next_steps: cond do
        not auth_ok -> "authenticate via API key or OAuth"
        not bill_ok -> "reduce usage or upgrade plan"
        true -> "call /api/v2/lsp/connect to mint ticket"
      end
    })
  end

  defp allow_billing(nil), do: {:error, :unauthorized}
  defp allow_billing(org) do
    case Lang.Billing.can_make_request?(org.id) do
      {:ok, :allowed} = ok -> ok
      {:error, :limit_exceeded} = err -> err
      other -> other
    end
  end

  defp mint_lsp_ticket(nil, _), do: {:error, :unauthorized}
  defp mint_lsp_ticket(_, nil), do: {:error, :unauthorized}
  defp mint_lsp_ticket(user, org) do
    ttl = 300
    scope = "lsp_ws"
    cid = derive_cid(user.id, org.id)
    claims = %{"sub" => user.id, "org" => org.id, "scope" => scope, "cid" => cid}
    {:ok, token} = Lang.Security.JWT.sign_ticket(claims, ttl: ttl)
    Lang.Events.track_event(%{
      event_type: "lsp_ticket_minted",
      user_id: user.id,
      organization_id: org.id,
      metadata: %{cid: cid, scope: scope}
    })
    {:ok, token, ttl, cid}
  end

  defp derive_cid(user_id, org_id) do
    base = :crypto.hash(:sha256, to_string(user_id) <> "|" <> to_string(org_id)) |> Base.encode16(case: :lower)
    "cid_" <> binary_part(base, 0, 16)
  end
end

