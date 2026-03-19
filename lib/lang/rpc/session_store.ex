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

  @doc """
  Store a session payload including auth context details.

  Merges `auth_session_id`, `user_id`, and `organization_id` into the stored map
  when present. Keeps entries small and ttl-bounded.
  """
  def put_with_context(request_id, map, ctx, ttl_sec \\ 600)
      when is_binary(request_id) and is_map(map) and is_map(ctx) do
    merged =
      map
      |> maybe_put(:auth_session_id, Map.get(ctx, :auth_session_id))
      |> maybe_put(:user_id, get_in(ctx, [:user, :id]))
      |> maybe_put(:organization_id, get_in(ctx, [:organization, :id]))

    put(request_id, merged, ttl_sec)
  end

  def get(request_id) when is_binary(request_id) do
    key = @prefix <> request_id

    case Redis.get(key) do
      {:ok, nil} -> {:error, :not_found}
      {:ok, json} -> Jason.decode(json)
      {:error, _} -> {:error, :store_failed}
    end
  end

  @doc """
  Fetch a session and verify it belongs to the given auth session id.
  Returns {:ok, map} when it matches; {:error, :forbidden} otherwise.
  """
  def get_authenticated(request_id, auth_session_id) when is_binary(request_id) do
    with {:ok, map} <- get(request_id) do
      case {Map.get(map, "auth_session_id") || Map.get(map, :auth_session_id), auth_session_id} do
        {nil, _} -> {:ok, map}
        {stored, provided} when stored == provided -> {:ok, map}
        _ -> {:error, :forbidden}
      end
    end
  end

  def touch(request_id, ttl_sec \\ 600) when is_binary(request_id) do
    key = @prefix <> request_id

    case Redis.expire(key, ttl_sec) do
      {:ok, 1} -> :ok
      _ -> {:error, :not_found}
    end
  end

  defp maybe_put(map, _k, nil), do: map
  defp maybe_put(map, k, v), do: Map.put(map, k, v)
end
