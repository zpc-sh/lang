defmodule Lang.JSONLD.Signature do
  @moduledoc """
  JSON-LD signing/verification utilities (feature-gated; off by default).

  Tier 1 (now): HS256 (HMAC-SHA256) signing for internal integrity checks.
  - Canonicalization uses stable-key JSON (deterministic key order). We can swap
    to RFC 8785 (JCS) later without affecting callers.

  Tier 2 (future): Ed25519 (JWS/Linked Data Proofs) or SSH signatures.

  This module does not change behavior unless you opt-in by enabling
  `JSONLD_SIGNING=on` in your environment and wiring calls in emission points.
  """

  @type proof :: %{
          optional(String.t()) => String.t()
        }

  @doc """
  Deterministically encode a JSON map by sorting keys recursively.
  Returns the canonical JSON (UTF-8) binary.
  """
  @spec canonical(map()) :: binary()
  def canonical(map) when is_map(map) do
    map
    |> sort_keys()
    |> Jason.encode!()
  end

  defp sort_keys(%{} = m) do
    m
    |> Enum.map(fn {k, v} -> {k, sort_keys(v)} end)
    |> Enum.sort_by(fn {k, _} -> k end)
    |> Enum.into(%{})
  end

  defp sort_keys([h | t]), do: [sort_keys(h) | sort_keys(t)]
  defp sort_keys([]), do: []
  defp sort_keys(x), do: x

  @doc """
  Sign a JSON map using HS256 (HMAC-SHA256).

  Options:
  - :key — binary secret key; defaults to `System.get_env("JSONLD_SIGNING_KEY")`
  - :kid — key id label (default "local:hs256")

  Returns {proof, canonical_json} suitable for attaching as an adjacent
  proof object.
  """
  @spec sign_hs256(map(), keyword()) :: {proof(), binary()}
  def sign_hs256(map, opts \\ []) when is_map(map) do
    canon = canonical(map)
    key = opts[:key] || System.get_env("JSONLD_SIGNING_KEY") || raise "missing JSONLD_SIGNING_KEY"
    kid = opts[:kid] || "local:hs256"
    ts = DateTime.utc_now() |> DateTime.to_iso8601()

    sig = :crypto.mac(:hmac, :sha256, key, canon) |> Base.url_encode64(padding: false)
    hash = :crypto.hash(:sha256, canon) |> Base.encode16(case: :lower)

    proof = %{
      "alg" => "HS256",
      "created" => ts,
      "hash" => "sha256:#{hash}",
      "sig" => sig,
      "kid" => kid,
      "canon" => "stable-key-json"
    }

    {proof, canon}
  end

  @doc """
  Verify HS256 proof against a JSON map.

  Options:
  - :key — binary secret key; defaults to `System.get_env("JSONLD_SIGNING_KEY")`

  Returns :ok | {:error, reason}.
  """
  @spec verify_hs256(map(), proof(), keyword()) :: :ok | {:error, term()}
  def verify_hs256(map, %{"alg" => "HS256"} = proof, opts \\ []) when is_map(map) do
    key = opts[:key] || System.get_env("JSONLD_SIGNING_KEY") || ""
    canon = canonical(map)

    with {:ok, _} <- verify_hash(proof, canon),
         {:ok, _} <- verify_sig_hs256(proof, key, canon) do
      :ok
    else
      err -> err
    end
  end

  def verify_hs256(_map, _proof, _opts), do: {:error, :unsupported_proof}

  defp verify_hash(%{"hash" => "sha256:" <> hex}, canon) do
    calc = :crypto.hash(:sha256, canon) |> Base.encode16(case: :lower)
    if calc == hex, do: {:ok, :hash_ok}, else: {:error, :bad_hash}
  end

  defp verify_hash(_, _), do: {:error, :missing_hash}

  defp verify_sig_hs256(%{"sig" => sig_b64}, key, canon) do
    calc = :crypto.mac(:hmac, :sha256, key, canon) |> Base.url_encode64(padding: false)
    if calc == sig_b64, do: {:ok, :sig_ok}, else: {:error, :bad_sig}
  end

  defp verify_sig_hs256(_, _, _), do: {:error, :missing_sig}
end
