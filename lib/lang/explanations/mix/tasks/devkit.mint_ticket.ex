defmodule Mix.Tasks.Devkit.MintTicket do
  use Mix.Task
  @shortdoc "Mint a short-lived dev ticket for WS/LSP connects"

  @moduledoc """
  Mints a Phoenix.Token for use as a short-lived ticket when connecting to WS/LSP
  endpoints (e.g., the proxy WS). Intended for dev and debugging.

      mix devkit.mint_ticket --user-id <uid> --org-id <oid> [--scope proxy_ws] [--ttl 300]

  Prints the token and example usage.
  """

  @impl true
  def run(argv) do
    Mix.Task.run("app.start")
    {opts, _, _} = OptionParser.parse(argv,
      strict: ["user-id": :string, "org-id": :string, scope: :string, ttl: :integer]
    )

    user_id = opts[:"user-id"] || System.get_env("DEV_USER_ID") || "dev-user"
    org_id = opts[:"org-id"] || System.get_env("DEV_ORG_ID") || "dev-org"
    scope = opts[:scope] || "proxy_ws"
    ttl = opts[:ttl] || 300

    claims = %{user_id: user_id, org_id: org_id, scope: scope}
    token = Lang.Dev.Ticket.mint(scope, claims, ttl: ttl)

    base = endpoint_url()
    Mix.shell().info("
Ticket (#{scope}, ttl=#{ttl}s):
")
    Mix.shell().info(token)
    Mix.shell().info("
Examples:
")
    Mix.shell().info("  # WS connect with query param
  wscat -c '#{to_ws_url(base)}/api/sessions/abc123/connect?ticket=#{token}'
")
    Mix.shell().info("  # Authorization header
  curl -H 'Authorization: Bearer #{token}' '#{to_ws_url(base)}/api/sessions/abc123/connect'
")
  end

  defp endpoint_url do
    # Try Endpoint.url/0 when available; fallback to env
    try do
      LangWeb.Endpoint.url()
    rescue
      _ -> System.get_env("APP_URL") || "http://localhost:4000"
    end
  end

  defp to_ws_url(url) when is_binary(url) do
    cond do
      String.starts_with?(url, "https://") -> String.replace_prefix(url, "https://", "wss://")
      String.starts_with?(url, "http://") -> String.replace_prefix(url, "http://", "ws://")
      true -> url
    end
  end
end
