defmodule LangWeb.Plugs.SentryUserContextPlug do
  @moduledoc """
  Enriches Sentry context with current user/org when available.

  Safe in all envs: no-ops if Sentry is not loaded.
  """
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    with true <- Code.ensure_loaded?(Sentry.Context) do
      conn = Plug.Conn.fetch_query_params(conn)
      user = conn.assigns[:current_user]
      org = conn.assigns[:current_org]
      auth_session_id = get_session(conn, :auth_session_id) || conn.assigns[:auth_session_id]
      req_id = Logger.metadata()[:request_id] || List.first(get_req_header(conn, "x-request-id"))
      current_provider =
        conn.assigns[:provider] || conn.assigns[:selected_provider] || conn.params["provider"]
      include_headers? = Application.get_env(:lang, :sentry, []) |> Keyword.get(:include_headers, true)
      include_query? = Application.get_env(:lang, :sentry, []) |> Keyword.get(:include_query_params, true)

      request_headers = if include_headers?, do: pick_headers(conn.req_headers), else: nil
      query_params = if include_query?, do: redact_params(conn.query_params || %{}), else: nil

      try do
        if user do
          Sentry.Context.set_user_context(%{
            id: user.id,
            email: Map.get(user, :email)
          })
        end

        org_extra =
          if org do
            # Safely compute org metrics
            org_user_count = safe_user_count(org)
            org_price = safe_price(org)

            %{
              org_id: org.id,
              org_name: Map.get(org, :name),
              org_slug: Map.get(org, :slug),
              org_subscription_tier: Map.get(org, :subscription_tier) |> to_string_safe(),
              org_subscription_status: Map.get(org, :subscription_status) |> to_string_safe(),
              org_features: snapshot_features(Map.get(org, :features)),
              org_user_count: org_user_count,
              org_subscription_price: org_price
            }
          else
            %{}
          end

        base = %{
          path: conn.request_path,
          method: conn.method,
          auth_session_id: auth_session_id,
          request_id: req_id,
          current_provider: current_provider
        }

        extra =
          base
          |> maybe_put(:request_headers, request_headers)
          |> maybe_put(:query_params, query_params)
          |> Map.merge(org_extra)

        Sentry.Context.set_extra_context(extra)
      rescue
        _ -> :ok
      end
    end

    conn
  end

  defp to_string_safe(nil), do: nil
  defp to_string_safe(v) when is_atom(v), do: Atom.to_string(v)
  defp to_string_safe(v), do: v

  defp snapshot_features(nil), do: nil
  defp snapshot_features(%{} = feats) do
    feats
    |> Map.keys()
    |> Enum.take(20)
  end

  defp safe_user_count(org) do
    try do
      Lang.Accounts.Organization.user_count(org)
    rescue
      _ -> nil
    end
  end

  defp safe_price(org) do
    try do
      tier = Map.get(org, :subscription_tier)
      if is_nil(tier), do: nil, else: Lang.Accounts.Organization.subscription_price(tier)
    rescue
      _ -> nil
    end
  end

  # Redact sensitive params from query string (shallow)
  defp redact_params(params) when is_map(params) do
    sens = sensitive_params_set()

    Enum.into(params, %{}, fn {k, v} ->
      if MapSet.member?(sens, String.downcase(to_string(k))) do
        {k, "[REDACTED]"}
      else
        {k, truncate_value(v)}
      end
    end)
  end

  defp redact_params(_), do: %{}

  defp truncate_value(v) when is_binary(v) do
    max = Application.get_env(:lang, :sentry, []) |> Keyword.get(:max_string, 200)
    if String.length(v) > max, do: String.slice(v, 0, max) <> "…", else: v
  end

  defp truncate_value(list) when is_list(list), do: Enum.map(list, &truncate_value/1)
  defp truncate_value(%{} = map), do: Enum.into(map, %{}, fn {k, v} -> {k, truncate_value(v)} end)
  defp truncate_value(other), do: other

  # Pick a small, safe header allowlist
  defp pick_headers(headers) when is_list(headers) do
    allow =
      Application.get_env(:lang, :sentry, [])
      |> Keyword.get(:header_allowlist, ["user-agent", "content-type", "accept", "x-request-id", "referer"])
      |> Enum.map(&String.downcase/1)
      |> MapSet.new()

    headers
    |> Enum.reduce(%{}, fn {k, v}, acc ->
      if MapSet.member?(allow, String.downcase(k)) do
        Map.put(acc, String.downcase(k), v)
      else
        acc
      end
    end)
  end

  defp pick_headers(_), do: %{}

  defp maybe_put(map, _k, nil), do: map
  defp maybe_put(map, k, v), do: Map.put(map, k, v)

  defp sensitive_params_set do
    default = [
      "password",
      "token",
      "api_key",
      "apikey",
      "authorization",
      "auth",
      "bearer",
      "secret",
      "key",
      "access_token",
      "refresh_token"
    ]

    Application.get_env(:lang, :sentry, [])
    |> Keyword.get(:sensitive_params, default)
    |> Enum.map(&String.downcase/1)
    |> MapSet.new()
  end
end
