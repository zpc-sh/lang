defmodule LangWeb.Api.V2.MCPBillingController do
  use LangWeb, :controller
  require Ash.Query

  alias Lang.MCP.Resources.Connection
  alias LangWeb.ApiError

  # GET /api/v2/mcp/billing/usage?period=current_month|last_month
  def usage(conn, %{"period" => period}) do
    user = conn.assigns.current_user

    case period_start(period) do
      {:ok, start_dt} ->
        connections =
          Connection
          |> Ash.Query.filter(user_id == ^user.id)
          |> Ash.Query.filter(created_at >= ^start_dt)
          |> Ash.Query.load([:server_config])
          |> Ash.read!()

        usage_summary = %{
          total_connections: length(connections),
          total_cost_cents: length(connections) * 25,
          by_server_type: group_by_server_type(connections),
          period: period
        }

        json(conn, usage_summary)

      {:error, :invalid_period} ->
        ApiError.json(conn, :bad_request, "Invalid period parameter", %{allowed: ["current_month", "last_month"]})
    end
  end

  def usage(conn, _params) do
    ApiError.json(conn, :bad_request, "Missing required parameter: period")
  end

  defp group_by_server_type(connections) do
    connections
    |> Enum.group_by(fn c -> c.server_config && c.server_config.server_type || :unknown end)
    |> Enum.map(fn {type, conns} -> {type, length(conns)} end)
    |> Enum.into(%{})
  end

  defp period_start("current_month") do
    now = DateTime.utc_now()
    {:ok, date} = Date.new(now.year, now.month, 1)
    {:ok, naive} = NaiveDateTime.new(date, ~T[00:00:00])
    DateTime.from_naive!(naive, "Etc/UTC")
    end

  defp period_start("last_month") do
    now = DateTime.utc_now()
    {year, month} = if now.month == 1, do: {now.year - 1, 12}, else: {now.year, now.month - 1}
    {:ok, date} = Date.new(year, month, 1)
    {:ok, naive} = NaiveDateTime.new(date, ~T[00:00:00])
    DateTime.from_naive!(naive, "Etc/UTC")
  end

  defp period_start(_), do: {:error, :invalid_period}
end
