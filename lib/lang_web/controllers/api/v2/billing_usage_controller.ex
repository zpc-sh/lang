defmodule LangWeb.Api.V2.BillingUsageController do
  use LangWeb, :controller
  alias LangWeb.AuthHelpers
  import Ash.Query

  @doc """
  GET /api/v2/billing/aggregates?granularity=hour|day|month&kind=api_requests|mcp_connections&from=ISO&to=ISO
  If organization_id is not provided, uses current user's org.
  """
  def aggregates(conn, params) do
    org_id = params["organization_id"] || get_org_id!(conn)
    gran = (params["granularity"] && String.to_atom(params["granularity"])) || nil
    kind = (params["kind"] && String.to_atom(params["kind"])) || nil
    from = parse_iso(params["from"])
    to = parse_iso(params["to"])

    result =
      Lang.Billing.Aggregate
      |> Ash.Query.for_read(:by_org_and_period)
      |> Ash.Query.set_arguments(%{
        organization_id: org_id,
        granularity: gran,
        kind: kind,
        from: from,
        to: to
      })
      |> Ash.read()

    case result do
      {:ok, list} -> json(conn, %{aggregates: Enum.map(list, &serialize/1)})
      {:error, reason} -> error(conn, reason)
    end
  end

  @doc """
  GET /api/v2/billing/summary
  Returns current-month usage summary for the current (or provided) organization.
  """
  def summary(conn, params) do
    org_id = params["organization_id"] || get_org_id!(conn)
    now = DateTime.utc_now()
    month_start = DateTime.beginning_of_month(now)

    # Pull day-level aggregates this month for both kinds
    with {:ok, api_agg} <- read_aggregates(org_id, :day, :api_requests, month_start, now),
         {:ok, mcp_agg} <- read_aggregates(org_id, :day, :mcp_connections, month_start, now) do
      api_total = Enum.reduce(api_agg, 0, fn a, acc -> acc + (a.total_requests || 0) end)
      mcp_total = Enum.reduce(mcp_agg, 0, fn a, acc -> acc + (a.total_mcp_connections || 0) end)

      total_size =
        Enum.reduce(api_agg, 0, fn a, acc -> acc + (a.total_content_size_bytes || 0) end)

      json(conn, %{
        "@context" => "https://lang.nulity.com/context/billing",
        organization_id: org_id,
        month_start: month_start,
        period_end: now,
        totals: %{
          api_requests: api_total,
          mcp_connections: mcp_total,
          api_content_size_bytes: total_size
        }
      })
    else
      {:error, reason} -> error(conn, reason)
    end
  end

  defp read_aggregates(org_id, granularity, kind, from, to) do
    Lang.Billing.Aggregate
    |> Ash.Query.for_read(:by_org_and_period)
    |> Ash.Query.set_arguments(%{
      organization_id: org_id,
      granularity: granularity,
      kind: kind,
      from: from,
      to: to
    })
    |> Ash.read()
  end

  defp get_org_id!(conn) do
    case AuthHelpers.current_org(conn) do
      %{id: org_id} -> org_id
      _ -> raise "No organization in context"
    end
  end

  defp parse_iso(nil), do: nil

  defp parse_iso(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end

  defp serialize(%Lang.Billing.Aggregate{} = a) do
    %{
      id: a.id,
      organization_id: a.organization_id,
      period_start: a.period_start,
      period_end: a.period_end,
      granularity: a.granularity,
      kind: a.kind,
      total_requests: a.total_requests,
      total_mcp_connections: a.total_mcp_connections,
      total_content_size_bytes: a.total_content_size_bytes
    }
  end

  defp error(conn, reason) do
    conn
    |> put_status(:internal_server_error)
    |> json(%{error: "Failed to load aggregates", details: inspect(reason)})
  end
end
