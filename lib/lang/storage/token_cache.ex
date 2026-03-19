defmodule Lang.Storage.TokenCache do
  @moduledoc """
  Tiny ETS-backed cache for short-lived Folder JWTs by scope.
  Not a long-running process; table is created on demand.
  """

  @table :folder_token_cache

  def get(scope) when is_binary(scope) do
    ensure()
    case :ets.lookup(@table, scope) do
      [{^scope, token, exp}] ->
        now = System.system_time(:second)
        if is_integer(exp) and exp > now + 5 do
          {:ok, token}
        else
          :expired
        end
      _ -> :miss
    end
  end

  def put(scope, token, expires_in) when is_binary(scope) and is_binary(token) do
    ensure()
    now = System.system_time(:second)
    exp = now + (expires_in || 900)
    true = :ets.insert(@table, {scope, token, exp})
    :ok
  end

  defp ensure do
    case :ets.whereis(@table) do
      :undefined -> :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
      _ -> :ok
    end
  end
end

