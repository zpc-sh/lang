defmodule LangWeb.SessionConnectController do
  use LangWeb, :controller
  alias LangWeb.AuthHelpers

  @doc """
  Mint a short-lived session ticket for a Markdown-LD session fence and return a proxy URL.

  Note: This is a minimal stub that issues a signed token. The actual
  proxy websocket endpoint should validate the token and establish the upstream
  (SSH/Unix/WS) connection.
  """
  def connect(conn, %{"id" => session_id} = _params) do
    user = AuthHelpers.current_user(conn)
    org = AuthHelpers.current_org(conn)

    if is_nil(user) or is_nil(org) do
      conn |> put_status(:unauthorized) |> json(%{error: "unauthorized"})
    else
      body = conn.body_params || %{}
      cap = Map.get(body, "cap", "interactive")
      cols = Map.get(body, "cols", 100)
      rows = Map.get(body, "rows", 28)
      mode = Map.get(body, "mode", "pty")
      proto = Map.get(body, "proto", "ssh")
      # Optional per-proto params (safe metadata, no secrets)
      host = Map.get(body, "host")
      port = Map.get(body, "port")
      ssh_user = Map.get(body, "user")
      ssh_fingerprint = Map.get(body, "fingerprint")
      unix_path = Map.get(body, "path")
      ldspolicy = Map.get(body, "policy") || Map.get(body, "lds:policy") || "attach"

      # Policy gate: static rules, plan limits, and optional Core Explanation Engine
      attrs = %{
        "lds:proto" => proto,
        "lds:policy" => ldspolicy,
        "lds:host" => host,
        "lds:port" => port,
        "lds:user" => ssh_user,
        "lds:fingerprint" => ssh_fingerprint,
        "lds:path" => unix_path,
        "cap" => cap,
        "mode" => mode,
        "cols" => cols,
        "rows" => rows
      }

      case Lang.Security.SessionPolicy.authorize_connect(user, org, attrs) do
        {:ok, :allowed, _ctx} -> :ok
        {:error, reason, details} ->
          _ = Lang.Events.track_event(%{
            event_type: "mdld_session_connect_denied",
            user_id: user.id,
            organization_id: org.id,
            metadata: %{session_id: session_id, reason: inspect(reason), details: details}
          })
          conn
          |> Plug.Conn.put_status(:forbidden)
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Phoenix.Controller.json(%{error: to_string(reason), details: details})
      end
      # Issue a short-lived signed token
      claims = %{
        "sub" => user.id,
        "org" => org.id,
        "session_id" => session_id,
        "proto" => proto,
        "cap" => cap,
        "cols" => cols,
        "rows" => rows,
        "mode" => mode,
        "exp" => DateTime.utc_now() |> DateTime.add(5 * 60, :second) |> DateTime.to_unix(),
        "nonce" => Base.encode16(:crypto.strong_rand_bytes(8), case: :lower),
        "host" => host,
        "port" => port,
        "user" => ssh_user,
        "fingerprint" => ssh_fingerprint,
        "path" => unix_path
      }

      # Sign with a stable salt for WS verification
      token = Phoenix.Token.sign(LangWeb.Endpoint, "session_ws_ticket", claims)

      # Stub websocket URL; the server-side proxy should mount a handler to validate this token
      # Using relative path allows the client to adjust ws/wss based on current scheme
      wss_url = "/ws/sessions/attach?ticket=" <> URI.encode(token)

      _ = Lang.Events.track_event(%{
        event_type: "mdld_session_connect_allowed",
        user_id: user.id,
        organization_id: org.id,
        metadata: Map.put(claims, "wss_url", wss_url)
      })

      resp = %{
        "wss_url" => wss_url,
        "ticket" => token,
        "provenance" => %{"runner" => "ssh-proxy", "version" => "0.0.1"}
      }

      conn
      |> put_resp_content_type("application/json")
      |> json(resp)
    end
  end
end
