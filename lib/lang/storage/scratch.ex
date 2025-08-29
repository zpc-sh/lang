defmodule Elixir.Lang.LSP.Lang.Lang.Storage.UpdateScratch do
  @moduledoc "Update scratch transformation stage"
  @behaviour Lang.LSP.Handler
  @lsp_method "lang.lang.storage.update_scratch"

  @impl true
  def method, do: @lsp_method

  @impl true
  def handle(params, ctx) when is_map(params) and is_map(ctx) do
    user_id = Map.get(ctx, "user_id") || Map.get(params, "user_id")
    session_id = Map.get(params, "session_id")
    stage = Map.get(params, "stage")
    data = Map.get(params, "data")

    case {user_id, session_id, stage, data} do
      {nil, _, _, _} ->
        {:error, "user_id is required"}

      {_, nil, _, _} ->
        {:error, "session_id is required"}

      {_, _, nil, _} ->
        {:error, "stage is required"}

      {_, _, _, nil} ->
        {:error, "data is required"}

      {user_id, session_id, stage, data} ->
        scratch_key = build_scratch_key(user_id, session_id, stage)

        # Store scratch data with metadata
        scratch_entry = %{
          user_id: user_id,
          session_id: session_id,
          stage: stage,
          data: data,
          updated_at: DateTime.utc_now(),
          version: get_next_version(scratch_key)
        }

        case store_scratch_data(scratch_key, scratch_entry) do
          :ok ->
            {:ok,
             %{
               updated: true,
               key: scratch_key,
               stage: stage,
               version: scratch_entry.version,
               updated_at: scratch_entry.updated_at
             }}

          {:error, reason} ->
            {:error, "Failed to update scratch: #{reason}"}
        end
    end
  end

  defp build_scratch_key(user_id, session_id, stage) do
    "scratch:#{user_id}:#{session_id}:#{stage}"
  end

  defp get_next_version(scratch_key) do
    case get_scratch_data(scratch_key) do
      {:ok, existing_data} ->
        Map.get(existing_data, :version, 0) + 1

      _ ->
        1
    end
  end

  defp store_scratch_data(key, data) do
    case get_storage_backend() do
      :redis ->
        store_in_redis(key, data)

      :ets ->
        store_in_ets(key, data)
    end
  end

  defp get_scratch_data(key) do
    case get_storage_backend() do
      :redis ->
        get_from_redis(key)

      :ets ->
        get_from_ets(key)
    end
  end

  defp get_storage_backend do
    if Process.whereis(Lang.Redis) do
      :redis
    else
      :ets
    end
  end

  defp store_in_redis(key, data) do
    try do
      case Jason.encode(data) do
        {:ok, json} ->
          # 24 hour TTL
          case Redix.command(Lang.Redis, ["SETEX", key, 86400, json]) do
            {:ok, "OK"} -> :ok
            _ -> {:error, "redis_store_failed"}
          end

        {:error, _} ->
          {:error, "json_encode_failed"}
      end
    rescue
      # Fallback to ETS
      _ -> store_in_ets(key, data)
    end
  end

  defp store_in_ets(key, data) do
    table_name = :scratch_storage

    # Ensure ETS table exists
    unless :ets.whereis(table_name) != :undefined do
      :ets.new(table_name, [:named_table, :public, :set])
    end

    try do
      :ets.insert(table_name, {key, data})
      :ok
    rescue
      _ -> {:error, "ets_store_failed"}
    end
  end

  defp get_from_redis(key) do
    try do
      case Redix.command(Lang.Redis, ["GET", key]) do
        {:ok, nil} ->
          {:error, :not_found}

        {:ok, json} ->
          case Jason.decode(json) do
            {:ok, data} -> {:ok, data}
            _ -> {:error, :json_decode_failed}
          end

        _ ->
          {:error, :redis_get_failed}
      end
    rescue
      _ -> get_from_ets(key)
    end
  end

  defp get_from_ets(key) do
    table_name = :scratch_storage

    case :ets.whereis(table_name) do
      :undefined ->
        {:error, :not_found}

      _ ->
        case :ets.lookup(table_name, key) do
          [{^key, data}] -> {:ok, data}
          _ -> {:error, :not_found}
        end
    end
  end
end
