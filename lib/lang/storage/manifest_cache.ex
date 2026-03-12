defmodule Lang.Storage.ManifestCache do
  @moduledoc """
  Tiny ETS cache for OCI manifests keyed by {owner, repo, reference}.
  TTL is short (default 60s) via Lang.Storage.Config.manifest_cache_ttl/0.
  """

  alias Lang.Storage.Config, as: SConfig
  @table :folder_manifest_cache

  def get(owner, repo, reference) do
    ensure()
    key = {owner, repo, reference}
    case :ets.lookup(@table, key) do
      [{^key, manifest, exp}] ->
        if exp > now() do
          {:ok, manifest}
        else
          :ets.delete(@table, key)
          :expired
        end
      _ -> :miss
    end
  end

  def put(owner, repo, reference, manifest) when is_map(manifest) do
    ensure()
    key = {owner, repo, reference}
    ttl = SConfig.manifest_cache_ttl()
    exp = now() + max(ttl, 1)
    true = :ets.insert(@table, {key, manifest, exp})
    :ok
  end

  defp now, do: System.system_time(:second)

  defp ensure do
    case :ets.whereis(@table) do
      :undefined -> :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
      _ -> :ok
    end
  end
end

