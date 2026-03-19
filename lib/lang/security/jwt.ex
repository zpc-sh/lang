defmodule Lang.Security.JWT do
  @moduledoc """
  Minimal JWT signer/verifier for short-lived tickets (RS256 preferred; HS256 fallback).

  Configuration via environment variables:
  - `LSP_JWT_KEYS` (JSON object of `{kid: pem, ...}`) and `LSP_JWT_ACTIVE_KID`
  - or `LSP_JWT_RS256_PRIV_PEM` / `LSP_JWT_RS256_PUB_PEM` (PEM strings)
  - or `LSP_JWT_HS256_SECRET` (octet secret)
  """

  @ttl_default 300

  @spec sign_ticket(map(), keyword()) :: {:ok, String.t()}
  def sign_ticket(claims, opts \\ []) when is_map(claims) do
    ttl = Keyword.get(opts, :ttl, @ttl_default)
    now = System.os_time(:second)
    claims = Map.merge(%{"iat" => now, "exp" => now + ttl}, claims)
    {jwk, alg, kid} = signer()
    header = %{"alg" => alg} |> maybe_put_kid(kid)
    {_, token} = JOSE.JWT.sign(jwk, header, claims) |> JOSE.JWS.compact()
    {:ok, token}
  end

  @spec verify_ticket(String.t()) :: {:ok, map()} | {:error, :invalid}
  def verify_ticket(token) when is_binary(token) do
    candidates = verifiers()
    Enum.reduce_while(candidates, {:error, :invalid}, fn {jwk, alg}, _acc ->
      case JOSE.JWT.verify_strict(jwk, [alg], token) do
        {true, %JOSE.JWT{fields: fields}, _} -> {:halt, {:ok, fields}}
        _ -> {:cont, {:error, :invalid}}
      end
    end)
  end

  defp signer do
    keys_json = System.get_env("LSP_JWT_KEYS")
    active_kid = System.get_env("LSP_JWT_ACTIVE_KID")
    pem = System.get_env("LSP_JWT_RS256_PRIV_PEM")
    secret = System.get_env("LSP_JWT_HS256_SECRET")

    if is_binary(keys_json) and String.trim(keys_json) != "" and is_binary(active_kid) and String.trim(active_kid) != "" do
      case Jason.decode(keys_json) do
        {:ok, map} when is_map(map) ->
          pem_active = Map.get(map, active_kid)
          if is_binary(pem_active) and String.trim(pem_active) != "" do
            {JOSE.JWK.from_pem(pem_active), "RS256", active_kid}
          else
            raise "Active kid not found or empty in LSP_JWT_KEYS"
          end
        _ -> raise "Invalid LSP_JWT_KEYS JSON"
      end
    else
      cond do
        is_binary(pem) and String.trim(pem) != "" ->
          jwk = JOSE.JWK.from_pem(pem)
          {jwk, "RS256", compute_kid(jwk)}
        is_binary(secret) and byte_size(secret) > 0 ->
          {JOSE.JWK.from_oct(secret), "HS256", nil}
        true -> raise "JWT signer not configured: set LSP_JWT_KEYS + LSP_JWT_ACTIVE_KID or LSP_JWT_RS256_PRIV_PEM or LSP_JWT_HS256_SECRET"
      end
    end
  end

  defp verifiers do
    keys_json = System.get_env("LSP_JWT_KEYS")
    pem_single = System.get_env("LSP_JWT_RS256_PUB_PEM") || System.get_env("LSP_JWT_RS256_PRIV_PEM")
    secret = System.get_env("LSP_JWT_HS256_SECRET")

    []
    |> then(fn acc ->
      if is_binary(keys_json) and String.trim(keys_json) != "" do
        case Jason.decode(keys_json) do
          {:ok, map} when is_map(map) ->
            Enum.reduce(map, acc, fn {_kid, pem}, a ->
              if is_binary(pem) and String.trim(pem) != "" do
                [{JOSE.JWK.from_pem(pem), "RS256"} | a]
              else
                a
              end
            end)
          _ -> acc
        end
      else
        acc
      end
    end)
    |> then(fn acc ->
      if is_binary(pem_single) and String.trim(pem_single) != "" do
        [{JOSE.JWK.from_pem(pem_single), "RS256"} | acc]
      else
        acc
      end
    end)
    |> then(fn acc ->
      if is_binary(secret) and byte_size(secret) > 0 do
        [{JOSE.JWK.from_oct(secret), "HS256"} | acc]
      else
        acc
      end
    end)
    |> case do
      [] -> raise("JWT verifier not configured")
      list -> Enum.reverse(list)
    end
  end

  defp compute_kid(jwk) do
    try do
      {:ok, thumb} = JOSE.JWK.thumbprint(jwk)
      Base.url_encode64(thumb, padding: false)
    rescue
      _ -> nil
    end
  end

  defp maybe_put_kid(map, nil), do: map
  defp maybe_put_kid(map, kid), do: Map.put(map, "kid", kid)
end

