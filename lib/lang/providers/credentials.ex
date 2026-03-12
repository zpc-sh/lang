defmodule Lang.Providers.Credentials do
  @moduledoc """
  Resolve provider API keys dynamically with the following precedence:

  1. opts[:api_key] (explicit per-request override)
  2. Organization-bound credential (opts[:organization_id])
  3. User-bound credential (opts[:user_id])
  4. Application env fallback (config :lang, :ai_providers)
  """

  alias Lang.Accounts.ProviderCredential
  require Logger

  @type provider :: :openai | :anthropic | :xai | :gemini

  @spec resolve_api_key(provider(), keyword() | map()) :: {:ok, String.t()} | {:error, term()}
  def resolve_api_key(provider, opts) do
    opts = normalize_opts(opts)

    meta = %{provider: provider, organization_id: opts[:organization_id], user_id: opts[:user_id]}

    :telemetry.span([:lang, :providers, :credentials, :resolve], meta, fn ->
      res =
        with {:override, nil} <- {:override, opts[:api_key]},
             {:org, nil} <- {:org, fetch_org_key(provider, opts[:organization_id])},
             {:user, nil} <- {:user, fetch_user_key(provider, opts[:user_id])},
             {:app, nil} <- {:app, fetch_app_env_key(provider)} do
          {:error, {:missing_api_key, provider}}
        else
          {:override, key} when is_binary(key) -> {:ok, key}
          {:org, key} when is_binary(key) -> {:ok, key}
          {:user, key} when is_binary(key) -> {:ok, key}
          {:app, key} when is_binary(key) -> {:ok, key}
        end

      measurements = %{status: match?({:ok, _}, res)}
      {measurements, res}
    end)
  end

  defp normalize_opts(%{} = map), do: Map.new(map)
  defp normalize_opts(list) when is_list(list), do: Map.new(list)
  defp normalize_opts(_), do: %{}

  defp fetch_app_env_key(provider) do
    case Application.get_env(:lang, :ai_providers) do
      nil -> nil
      cfg when is_list(cfg) or is_map(cfg) ->
        key_field =
          case provider do
            :openai -> :openai_api_key
            :anthropic -> :anthropic_api_key
            :xai -> :xai_api_key
            :gemini -> :gemini_api_key
          end

        cfg[key_field]
    end
  end

  defp fetch_org_key(_provider, nil), do: nil
  defp fetch_org_key(provider, org_id) do
    cache_lookup({:org, provider, org_id}) ||
      case ProviderCredential.list_by_org_and_provider(organization_id: org_id, provider: provider) do
        {:ok, [cred | _]} ->
          decrypt(cred)
          |> tap(fn
            nil -> :noop
            key -> cache_store({:org, provider, org_id}, key)
          end)

        _ -> nil
      end
  end

  defp fetch_user_key(_provider, nil), do: nil
  defp fetch_user_key(provider, user_id) do
    cache_lookup({:user, provider, user_id}) ||
      case ProviderCredential.list_by_user_and_provider(user_id: user_id, provider: provider) do
        {:ok, [cred | _]} ->
          decrypt(cred)
          |> tap(fn
            nil -> :noop
            key -> cache_store({:user, provider, user_id}, key)
          end)

        _ -> nil
      end
  end

  defp decrypt(%{encrypted_api_key: enc}) do
    case Lang.Security.Encryption.decrypt(enc) do
      {:ok, key} -> key
      _ -> nil
    end
  end

  # Simple ETS cache with TTL
  @table :lang_provider_creds_cache

  defp cache_lookup(key) do
    ensure_table()
    case :ets.lookup(@table, key) do
      [{^key, value, expires_at}] ->
        if System.monotonic_time(:millisecond) < expires_at do
          value
        else
          :ets.delete(@table, key)
          nil
        end
      _ -> nil
    end
  end

  defp cache_store(key, value) do
    ensure_table()
    ttl = cache_ttl_ms()
    :ets.insert(@table, {key, value, System.monotonic_time(:millisecond) + ttl})
    :ok
  end

  defp ensure_table do
    case :ets.info(@table) do
      :undefined -> :ets.new(@table, [:named_table, :set, :public, read_concurrency: true])
      _ -> @table
    end
  end

  defp cache_ttl_ms do
    case Application.get_env(:lang, :provider_credentials) do
      nil -> 60_000
      cfg -> cfg[:cache_ttl_ms] || 60_000
    end
  end
end
