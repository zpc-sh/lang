#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="$ROOT_DIR/artifacts/three-body-lock"
mkdir -p "$OUT_DIR"

repo_state() {
  local repo_path="$1"
  local label="$2"
  if [ ! -d "$repo_path/.git" ]; then
    echo "{\"project\":\"$label\",\"present\":false}"
    return
  fi
  local head branch dirty
  head="$(git -C "$repo_path" rev-parse HEAD 2>/dev/null || echo unknown)"
  branch="$(git -C "$repo_path" rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"
  if [ -n "$(git -C "$repo_path" status --porcelain 2>/dev/null || true)" ]; then
    dirty=true
  else
    dirty=false
  fi
  echo "{\"project\":\"$label\",\"present\":true,\"head\":\"$head\",\"branch\":\"$branch\",\"dirty\":$dirty}"
}

self_name="$(basename "$ROOT_DIR")"
loci="$(repo_state "$ROOT_DIR/../loci" "loci")"
mu="$(repo_state "$ROOT_DIR/../mu" "mu")"
lang="$(repo_state "$ROOT_DIR/../lang" "lang")"

generated_at_utc="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

cat > "$OUT_DIR/snapshot.json" <<JSON
{
  "kind": "three_body_lock.snapshot.v0",
  "generated_at_utc": "$generated_at_utc",
  "self_project": "$self_name",
  "repos": {
    "loci": $loci,
    "mu": $mu,
    "lang": $lang
  },
  "contract_surface_version": "LOCI_EVENT_CHAIN/0.1",
  "runtime_chain_status": "unknown",
  "proof_status": "unknown"
}
JSON

cat > "$OUT_DIR/snapshot.md" <<MD
# Three-Body Lock Snapshot

Generated: $generated_at_utc

- self_project: $self_name
- contract_surface_version: LOCI_EVENT_CHAIN/0.1
- runtime_chain_status: unknown
- proof_status: unknown
MD

echo "three_body_lock_snapshot=ok"
echo "snapshot_json=$OUT_DIR/snapshot.json"
echo "snapshot_md=$OUT_DIR/snapshot.md"
