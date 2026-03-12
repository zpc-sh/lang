defmodule Lang.Security.Encryption do
  @moduledoc """
  AES-GCM encryption utilities for securing sensitive secrets at rest.

  Stores values as a compact string: "v1:base64(iv):base64(ciphertext):base64(tag)".
  Key is provided via `Lang.Security.Secrets.encryption_key/0` (Base64).
  """

  @version "v1"

  @spec encrypt(String.t()) :: String.t()
  def encrypt(plaintext) when is_binary(plaintext) do
    key = get_key()
    iv = :crypto.strong_rand_bytes(12)
    {ciphertext, tag} =
      :crypto.crypto_one_time_aead(:aes_256_gcm, key, iv, plaintext, <<>>, true)

    Enum.join([
      @version,
      Base.encode64(iv, padding: false),
      Base.encode64(ciphertext, padding: false),
      Base.encode64(tag, padding: false)
    ], ":")
  end

  @spec decrypt(String.t()) :: {:ok, String.t()} | {:error, term()}
  def decrypt(enc) when is_binary(enc) do
    case String.split(enc, ":", parts: 4) do
      [version, iv_b64, ct_b64, tag_b64] when version == @version ->
        with {:ok, iv} <- safe_decode64(iv_b64),
             {:ok, ct} <- safe_decode64(ct_b64),
             {:ok, tag} <- safe_decode64(tag_b64) do
          key = get_key()

          case :crypto.crypto_one_time_aead(:aes_256_gcm, key, iv, ct, <<>>, tag, false) do
            plaintext when is_binary(plaintext) -> {:ok, plaintext}
            _ -> {:error, :decrypt_failed}
          end
        else
          _ -> {:error, :invalid_format}
        end

      _ ->
        {:error, :invalid_format}
    end
  end

  defp get_key do
    # Expect a base64-encoded 32-byte key from secrets
    key_b64 = Lang.Security.Secrets.encryption_key()
    case Base.decode64(key_b64) do
      {:ok, key} when byte_size(key) == 32 -> key
      _ -> raise "Invalid ENCRYPTION_KEY: must be base64-encoded 32 bytes"
    end
  end

  defp safe_decode64(v) do
    case Base.decode64(v, padding: false) do
      {:ok, bin} -> {:ok, bin}
      :error -> {:error, :bad_b64}
    end
  end
end
