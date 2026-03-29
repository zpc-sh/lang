defmodule LangWeb.Plugs.SentryParamsRedactionPlug do
  @moduledoc """
  Adds a redacted snapshot of request params to Sentry extra context.

  - Runs after Plug.Parsers (params available)
  - Redacts common sensitive keys (token, password, api_key, auth, secret...)
  - Truncates long strings and limits depth to avoid heavy payloads
  - Handles Plug.Upload structs by recording filename and content_type only
  - No-ops if Sentry is not loaded
  """
  import Plug.Conn

  # Limits are configurable via config :lang, :sentry
  # Defaults are provided in config/config.exs

  def init(opts), do: opts

  def call(conn, _opts) do
    with true <- Code.ensure_loaded?(Sentry.Context) do
      conn = Plug.Conn.fetch_query_params(conn)
      params = conn.params || %{}

      if include_body_params?() do
        redacted =
          params
          |> redact_recursive(0)
          |> limit_size()

        try do
          Sentry.Context.set_extra_context(%{body_params: redacted})
        rescue
          _ -> :ok
        end
      end
    end

    conn
  end

  defp redact_recursive(%Plug.Upload{filename: fnm, content_type: ct}, _depth), do: %{upload: %{filename: fnm, content_type: ct}}
  defp redact_recursive(%Plug.Upload{} = up, _depth), do: %{upload: %{filename: Map.get(up, :filename)}}

  defp redact_recursive(map, depth) when is_map(map) do
    if depth >= max_depth() do
      "[TRUNCATED_MAP]"
    else
      Enum.into(map, %{}, fn {k, v} ->
        key = to_string(k)
        if sensitive_key?(key) do
          {k, "[REDACTED]"}
        else
          {k, redact_recursive(v, depth + 1)}
        end
      end)
    end
  end

  defp redact_recursive(list, depth) when is_list(list) do
    if depth >= max_depth() do
      "[TRUNCATED_LIST]"
    else
      list
      |> Enum.take(max_list())
      |> Enum.map(&redact_recursive(&1, depth + 1))
    end
  end

  defp redact_recursive(val, _depth) when is_binary(val) do
    ms = max_string()
    if String.length(val) > ms, do: String.slice(val, 0, ms) <> "…", else: val
  end

  defp redact_recursive(other, _depth), do: other

  defp sensitive_key?(key) do
    MapSet.member?(sensitive_params_set(), String.downcase(key))
  end

  defp limit_size(map) when is_map(map) do
    # Keep top-level keys deterministic and small; drop extras if too many
    map
    |> Enum.take(top_level_keys())
    |> Enum.into(%{})
  end
  defp limit_size(other), do: other

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

  defp include_body_params? do
    Application.get_env(:lang, :sentry, [])
    |> Keyword.get(:include_body_params, true)
  end

  # Config helpers (pull from :lang, :sentry)
  defp max_depth do
    Application.get_env(:lang, :sentry, [])
    |> Keyword.get(:max_depth, 3)
  end

  defp max_string do
    Application.get_env(:lang, :sentry, [])
    |> Keyword.get(:max_string, 200)
  end

  defp max_list do
    Application.get_env(:lang, :sentry, [])
    |> Keyword.get(:max_list, 50)
  end

  defp top_level_keys do
    Application.get_env(:lang, :sentry, [])
    |> Keyword.get(:top_level_keys, 50)
  end
end
