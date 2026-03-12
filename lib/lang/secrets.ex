defmodule Lang.Secrets do
  use AshAuthentication.Secret

  def secret_for(
        [:authentication, :tokens, :signing_secret],
        Lang.Accounts.User,
        _opts,
        _context
      ) do
    case Application.fetch_env(:lang, :token_signing_secret) do
      {:ok, secret} ->
        {:ok, secret}

      :error ->
        # Fallback to Phoenix secret key base
        case Application.fetch_env(:lang, LangWeb.Endpoint) do
          {:ok, endpoint_config} ->
            secret = Keyword.get(endpoint_config, :secret_key_base)
            {:ok, secret}

          :error ->
            {:error, "No signing secret configured"}
        end
    end
  end

  def secret_key_base do
    case Application.fetch_env(:lang, LangWeb.Endpoint) do
      {:ok, endpoint_config} ->
        Keyword.get(endpoint_config, :secret_key_base)

      :error ->
        "default-dev-secret-key-base-change-in-production"
    end
  end
end
