defmodule Lang.Dev.Ticket do
  @moduledoc """
  Minimal ticket mint/verify for dev & prod WS/LSP connects.

  Uses Phoenix.Token with a scope to create short-lived tokens that carry
  user/org context and a scope (e.g., "proxy_ws").
  """

  @default_ttl 300 # 5 minutes

  def mint(scope, claims, opts \ []) when is_binary(scope) and is_map(claims) do
    ttl = Keyword.get(opts, :ttl, @default_ttl)
    salt = salt_for(scope)
    Phoenix.Token.sign(LangWeb.Endpoint, salt, claims, max_age: ttl)
  end

  def verify(scope, token, opts \ []) do
    ttl = Keyword.get(opts, :ttl, @default_ttl)
    salt = salt_for(scope)
    Phoenix.Token.verify(LangWeb.Endpoint, salt, token, max_age: ttl)
  end

  defp salt_for(scope), do: "ticket:" <> scope
end
