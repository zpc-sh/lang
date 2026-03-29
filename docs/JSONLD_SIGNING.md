% JSON‑LD Signing (Feature‑Gated)

This repository includes a scaffold to sign and verify JSON‑LD payloads for
integrity. Signing is disabled by default and only enabled when you opt‑in.

## Status
- Tier 1 (now): HS256 (HMAC‑SHA256) signing/verification
- Tier 2 (future): Ed25519/JWS or SSH signatures for public verification

## Why
- Prevent untrusted agents from injecting payloads by ensuring the server signs
  canonical JSON before distribution.

## Canonicalization
- Uses a simple stable‑key JSON encoder (deterministic key order) for now.
- Can be upgraded to RFC 8785 (JCS) later without API changes.

## API

```
# Canonicalize
canon = Lang.JSONLD.Signature.canonical(json)

# Sign (HS256)
{proof, canon} = Lang.JSONLD.Signature.sign_hs256(json)

# Verify (HS256)
:ok = Lang.JSONLD.Signature.verify_hs256(json, proof)
```

Attach `proof` as an adjacent object (do not mutate the JSON‑LD payload), for
example as a fenced block near the payload in Markdown‑LD or in a sidecar file.

## Enabling (Optional)
- Signing is OFF by default. To enable HS256 signing where you emit JSON‑LD,
  set a secret key and guard the call sites:

```
export JSONLD_SIGNING=on
export JSONLD_SIGNING_KEY="$(openssl rand -base64 32)"
```

Then in emission code (e.g., MCP broker or an export endpoint):

```
if System.get_env("JSONLD_SIGNING") == "on" do
  {proof, _canon} = Lang.JSONLD.Signature.sign_hs256(json)
  # attach proof alongside json
end
```

## Future: Public‑Key Attestation
- Ed25519 or SSH signatures allow third parties to verify without shared secrets.
- Recommended envelope (detached):

```
{
  "input_hash": "sha256:…",
  "sig_alg": "ed25519",
  "signature": "<base64url>",
  "kid": "key‑id",
  "namespace": "lang-jsonld",
  "ts": "2025-08-28T12:34:56Z"
}
```

## Safety
- Never `String.to_atom/1` on JSON inputs.
- Keep signatures out of the JSON‑LD payload (use adjacent proofs) for stable
  canonicalization.
- Log normalize/verify failures; do not crash.

