defmodule Lang.Workers.BillingCleanupUsageWorker do
  use Oban.Worker, queue: :cleanup, max_attempts: 3
  require Logger
  import Ash.Query

  @impl true
  def perform(%Oban.Job{args: args}) do
    days = args["retention_days"] || 400
    cutoff = DateTime.add(DateTime.utc_now(), -days * 86_400, :second)

    deleted1 = delete_older_events(cutoff)
    deleted2 = delete_older_usage(cutoff)
    deleted3 = delete_older_aggregates(cutoff)

    {:ok,
     %{deleted_events: deleted1, deleted_usage_records: deleted2, deleted_aggregates: deleted3}}
  rescue
    e ->
      Logger.error("CleanupUsageWorker failed", error: Exception.message(e))
      :error
  end

  defp delete_older_events(cutoff) do
    q = Lang.Events.ApiUsageEvent |> filter(inserted_at < ^cutoff)

    case Ash.destroy(q) do
      {:ok, _} -> :ok
      _ -> :error
    end
  end

  defp delete_older_usage(cutoff) do
    q = Lang.Billing.UsageRecord |> filter(inserted_at < ^cutoff)

    case Ash.destroy(q) do
      {:ok, _} -> :ok
      _ -> :error
    end
  end

  defp delete_older_aggregates(cutoff) do
    q = Lang.Billing.Aggregate |> filter(inserted_at < ^cutoff)

    case Ash.destroy(q) do
      {:ok, _} -> :ok
      _ -> :error
    end
  end
end
