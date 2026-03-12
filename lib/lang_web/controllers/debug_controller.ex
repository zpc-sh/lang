defmodule LangWeb.DebugController do
  use LangWeb, :controller

  def sentry_boom(conn, _params) do
    raise("Sentry test error from /dev/sentry/boom")
  end

  def sentry_boom_json(conn, _params) do
    # Access params to ensure Plug.Parsers has run; SentryParamsRedactionPlug will attach redacted snapshot
    _ = conn.params
    raise("Sentry test error from /api/dev/sentry/boom with params")
  end
end
