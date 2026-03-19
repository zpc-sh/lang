
defmodule Lang.Events.TypeRegistry do
  @moduledoc """
  Canonical registry for event types and their categories.

  - Avoids drift by keeping a single source of truth for event routing
  - Supports exact matches and prefix-based categories
  - Allows extension via `config :lang, :events, extra: %{exact: %{}, prefixes: %{}}`
  """

  @type category :: :user_activity | :api_usage | :performance | :billing

  @doc """
  Resolve an event type (string or atom) to a category atom.
  Returns {:ok, category} or :unknown.
  """
  @spec resolve(String.t() | atom()) :: {:ok, category()} | :unknown
  def resolve(type) when is_atom(type), do: resolve(to_string(type))
  def resolve(type) when is_binary(type) do
    type = String.trim(type)
    {exact, prefixes} = load()

    case Map.get(exact, type) do
      nil ->
        case Enum.find(prefixes, fn {prefix, _cat} -> String.starts_with?(type, prefix) end) do
          {_, cat} -> {:ok, cat}
          nil -> :unknown
        end

      cat -> {:ok, cat}
    end
  end

  @doc """
  Export the merged registry as `{exact_map, prefixes_map}` for docs/tools.
  """
  @spec export() :: {map(), map()}
  def export do
    {exact, prefixes_list} = load()
    prefixes = Map.new(prefixes_list)
    {exact, prefixes}
  end

  defp load do
    cfg = Application.get_env(:lang, :events, [])
    extra = (cfg[:extra] || %{}) |> normalize_extra()

    exact =
      default_exact()
      |> Map.merge(extra.exact)

    prefixes =
      default_prefixes()
      |> Map.merge(extra.prefixes)
      |> Enum.to_list()

    {exact, prefixes}
  end

  defp normalize_extra(%{exact: e, prefixes: p}) when is_map(e) and is_map(p), do: %{exact: e, prefixes: p}
  defp normalize_extra(_), do: %{exact: %{}, prefixes: %{}}

  # Exact event types
  defp default_exact do
    %{
      # User activity
      "user_login_success" => :user_activity,
      "user_login_failed" => :user_activity,
      "user_registered" => :user_activity,
      "user_logged_out" => :user_activity,
      "password_reset_requested" => :user_activity,
      "password_reset_completed" => :user_activity,
      "api_key_created" => :user_activity,
      "api_key_revoked" => :user_activity,

      # API usage
      "api_call_made" => :api_usage,
      "api_call_failed" => :api_usage,
      "rate_limit_exceeded" => :api_usage,
      "usage_limit_exceeded" => :api_usage,
      "billing_event" => :api_usage,
      "mcp_connection_charge" => :api_usage,
      "lsp_ticket_minted" => :api_usage,
      "performance_metrics_collected" => :api_usage,

      # MCP connection events
      "mcp_connection_created" => :api_usage,
      "mcp_connection_destroyed" => :api_usage,
      "mcp_client_connected" => :user_activity,
      "mcp_client_disconnected" => :user_activity,
      "mcp_stream_created" => :user_activity,
      "mcp_stream_completed" => :user_activity,
      "mcp_stream_error" => :user_activity
    }
  end

  # Prefix-based categories
  defp default_prefixes do
    %{
      # Markdown-LD session audit events
      "mdld_session_" => :user_activity
    }
  end
end
