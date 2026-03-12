defmodule Lang.Proxy.Intent do
  @moduledoc """
  Signed intent tokens for sensitive operations (ssh/fs/lsp bootstrap).

  Tokens are HMAC-SHA256 signed JSON with a shared secret. Structure:
  %{
    "org_id" => org_id,
    "user_id" => user_id,
    "service" => service,
    "method" => method,
    "scope" => ["ssh:bootstrap"],
    "exp" => unix_ts,
    "nonce" => random
  }
  """

  @algo :sha256

  @spec sign(map()) :: {:ok, String.t()} | {:error, term()}
  def sign(claims) when is_map(claims) do
    with {:ok, secret} <- secret() do
      payload = Jason.encode!(claims)
      sig = :crypto.mac(:hmac, @algo, secret, payload) |> Base.url_encode64(padding: false)
      {:ok, Base.url_encode64(payload, padding: false) <> "." <> sig}
    end
  rescue
    e -> {:error, e}
  end

  @spec verify(String.t()) :: {:ok, map()} | {:error, term()}
  def verify(token) when is_binary(token) do
    with {:ok, secret} <- secret(),
         [payload_b64, sig_b64] <- String.split(token, "."),
         {:ok, payload} <- Base.url_decode64(payload_b64, padding: false),
         {:ok, sig} <- Base.url_decode64(sig_b64, padding: false),
         ^sig <- :crypto.mac(:hmac, @algo, secret, payload),
         {:ok, claims} <- Jason.decode(payload) do
      check_exp(claims)
    else
      _ -> {:error, :invalid_intent}
    end
  end

  defp check_exp(%{"exp" => exp} = claims) when is_integer(exp) do
    now = System.os_time(:second)
    if exp >= now, do: {:ok, claims}, else: {:error, :expired}
  end
  defp check_exp(claims), do: {:ok, claims}

  defp secret do
    case Application.get_env(:lang, :proxy_intent_secret) do
      s when is_binary(s) and byte_size(s) >= 16 -> {:ok, s}
      _ -> {:error, :missing_secret}
    end
  end
end

