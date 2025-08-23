defmodule Lang.Migration.ApiUsageToEvents do
  @moduledoc """
  Migration module to convert from the old APIUsage system to the new event-based system.

  Run this migration with: Lang.Migration.ApiUsageToEvents.migrate()
  """

  alias Lang.Accounts.APIUsage
  alias Lang.Events.ApiUsageEvent
  alias Lang.Repo
  import Ecto.Query
  require Logger

  @batch_size 1000

  def migrate do
    Logger.info("Starting API Usage to Events migration...")

    total = Repo.aggregate(APIUsage, :count)
    Logger.info("Total records to migrate: #{total}")

    migrated = migrate_in_batches()

    Logger.info("Migration complete. Migrated #{migrated} records.")
    {:ok, migrated}
  end

  defp migrate_in_batches(offset \\ 0, total_migrated \\ 0) do
    query =
      from(u in APIUsage,
        order_by: [asc: u.inserted_at],
        limit: @batch_size,
        offset: ^offset
      )

    case Repo.all(query) do
      [] ->
        total_migrated

      records ->
        migrated_count = migrate_batch(records)
        new_total = total_migrated + migrated_count

        if rem(new_total, 10_000) == 0 do
          Logger.info("Progress: #{new_total} records migrated")
        end

        migrate_in_batches(offset + @batch_size, new_total)
    end
  end

  defp migrate_batch(records) do
    events =
      records
      |> Enum.map(&convert_to_event/1)
      |> Enum.reject(&is_nil/1)

    case Repo.insert_all(ApiUsageEvent, events, on_conflict: :nothing) do
      {count, _} -> count
      _ -> 0
    end
  end

  defp convert_to_event(usage) do
    # Get organization_id from user
    org_id = get_user_organization_id(usage.user_id)

    if org_id do
      %{
        id: Ecto.UUID.generate(),
        user_id: usage.user_id,
        organization_id: org_id,
        operation_type: usage.operation_type,
        content_format: usage.format,
        content_size: usage.content_size_bytes || 0,
        processing_time_ms: usage.processing_time_ms,
        request_id: usage.request_id,
        user_agent: usage.user_agent,
        ip_address: usage.ip_address,
        success: usage.status == :success,
        rate_limited: usage.status == :rate_limited,
        error_type: usage.error_type,
        metadata: %{
          "month_year" => usage.month_year,
          "migrated_from" => "api_usage",
          "original_id" => usage.id
        },
        inserted_at: usage.inserted_at,
        updated_at: usage.updated_at
      }
    else
      Logger.warn("Skipping record #{usage.id} - no organization found for user #{usage.user_id}")
      nil
    end
  end

  defp get_user_organization_id(user_id) do
    query = from(u in Lang.Accounts.User, where: u.id == ^user_id, select: u.organization_id)
    Repo.one(query)
  end

  @doc """
  Verify migration by comparing counts
  """
  def verify_migration do
    old_count = Repo.aggregate(APIUsage, :count)

    new_count =
      Repo.aggregate(ApiUsageEvent, :count, filter: [metadata: %{"migrated_from" => "api_usage"}])

    Logger.info("Old APIUsage records: #{old_count}")
    Logger.info("Migrated ApiUsageEvent records: #{new_count}")
    Logger.info("Difference: #{old_count - new_count}")

    {:ok, %{old: old_count, new: new_count, difference: old_count - new_count}}
  end
end
