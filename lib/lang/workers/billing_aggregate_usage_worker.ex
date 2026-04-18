defmodule Lang.Workers.BillingAggregateUsageWorker do
  use Oban.Worker, queue: :billing, max_attempts: 3
  require Logger
  import Ash.Query
  alias Lang.AshHelpers

  @impl true
  def perform(%Oban.Job{args: args}) do
    org_id = args["organization_id"]
    gran = safe_to_atom(args["granularity"] || "hour", :hour)
    now = DateTime.utc_now()
    {period_start, period_end} = period_bounds(now, gran)

    # Aggregate API usage events
    api_events =
      Lang.Events.ApiUsageEvent
      |> filter(inserted_at >= ^period_start and inserted_at < ^period_end)
      |> maybe_org(org_id)
      |> Ash.read!()

    total_requests = length(api_events)

    total_size =
      Enum.reduce(api_events, 0, fn e, acc ->
        acc + (e.content_size || e.content_size_bytes || 0)
      end)

    # Aggregate metered usage records
    usage_records =
      Lang.Billing.UsageRecord
      |> filter(occurred_at >= ^period_start and occurred_at < ^period_end)
      |> maybe_org(org_id)
      |> Ash.read!()

    total_mcp =
      Enum.count(usage_records, &(&1.kind == "mcp_connection" || &1.kind == :mcp_connection))

    upsert_aggregate(
      org_id,
      period_start,
      period_end,
      gran,
      :api_requests,
      total_requests,
      total_mcp,
      total_size
    )

    {:ok, %{period_start: period_start, period_end: period_end, granularity: gran}}
  rescue
    e ->
      Logger.error("AggregateUsageWorker failed", error: Exception.message(e))
      :error
  end

  defp period_bounds(now, :hour) do
    start = %{now | minute: 0, second: 0, microsecond: {0, 0}}
    {start, DateTime.add(start, 3600, :second)}
  end

  defp period_bounds(now, :day) do
    start = %{now | hour: 0, minute: 0, second: 0, microsecond: {0, 0}}
    {start, DateTime.add(start, 86_400, :second)}
  end

  defp period_bounds(now, :month) do
    start = DateTime.beginning_of_month(now)
    {start, DateTime.add(start, 31 * 86_400, :second)}
  end

  defp upsert_aggregate(org_id, ps, pe, gran, kind, total_requests, total_mcp, total_size) do
    attrs = [
      organization_id: org_id,
      period_start: ps,
      period_end: pe,
      granularity: gran,
      kind: kind,
      total_requests: total_requests,
      total_mcp_connections: total_mcp,
      total_content_size_bytes: total_size
    ]

    case find_existing(org_id, ps, pe, gran, kind) do
      {:ok, nil} -> Ash.create(Lang.Billing.Aggregate, attrs)
      {:ok, agg} -> Ash.update(agg, attrs)
      _ -> :ok
    end
  end

  defp find_existing(org_id, ps, pe, gran, kind) do
    Lang.Billing.Aggregate
    |> AshHelpers.scope_to_org(org_id)
    |> filter(
      period_start == ^ps and period_end == ^pe and granularity == ^gran and kind == ^kind
    )
    |> Ash.read_one()
  end

  defp maybe_org(queryable, nil), do: queryable
  defp maybe_org(queryable, org), do: AshHelpers.scope_to_org(queryable, org)

  defp safe_to_atom(nil, default_value), do: default_value

  defp safe_to_atom(string_value, default_value) when is_binary(string_value) do
    try do
      String.to_existing_atom(string_value)
    rescue
      ArgumentError ->
        Logger.warning("Security Warning: Attempted atom table exhaustion with string: #{inspect(string_value)}")
        default_value
    end
  end

  defp safe_to_atom(atom_value, _) when is_atom(atom_value), do: atom_value
end
