defmodule Lang.RPC.SessionStore do
  @moduledoc """
  Ephemeral session/stream state in Redis for JSON-RPC.

  Keep entries small (a few KB) and short-lived.
  """

  alias Lang.Redis

  @prefix "rpc:session:"

  def put(request_id, map, ttl_sec \\ 600) when is_binary(request_id) and is_map(map) do
    key = @prefix <> request_id
    with {:ok, json} <- Jason.encode(map),
         {:ok, _} <- Redis.setex(key, ttl_sec, json) do
      :ok
    else
      _ -> {:error, :store_failed}
    end
  end

  def get(request_id) when is_binary(request_id) do
    key = @prefix <> request_id
    case Redis.get(key) do
      {:ok, nil} -> {:error, :not_found}
      {:ok, json} -> Jason.decode(json)
      {:error, _} -> {:error, :store_failed}
    end
  end

  def touch(request_id, ttl_sec \\ 600) when is_binary(request_id) do
    key = @prefix <> request_id
    case Redis.expire(key, ttl_sec) do
      {:ok, 1} -> :ok
      _ -> {:error, :not_found}
    end
  end
end

