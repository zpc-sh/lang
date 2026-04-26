#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "$0")/../.." && pwd)"
BUNDLE="$ROOT/../loci/loci/chatgpt/specs/mulsp-handoff-bundle.sha256"

if [[ ! -f "$BUNDLE" ]]; then
  echo "missing bundle: $BUNDLE" >&2
  exit 1
fi

echo "verifying bundle paths exist..."
missing=0
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  hash="${line%%  *}"
  rel="${line#*  }"
  [[ -z "$hash" || -z "$rel" ]] && continue
  if [[ ! -f "$ROOT/../loci/$rel" ]]; then
    echo "missing file: ../loci/$rel" >&2
    missing=1
  fi
done < "$BUNDLE"

if [[ "$missing" -ne 0 ]]; then
  exit 1
fi

echo "verifying sha256 digests..."
if command -v sha256sum >/dev/null 2>&1; then
  (
    cd "$ROOT/../loci"
    sha256sum -c "loci/chatgpt/specs/mulsp-handoff-bundle.sha256"
  )
elif command -v shasum >/dev/null 2>&1; then
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    expected="${line%%  *}"
    rel="${line#*  }"
    actual="$(shasum -a 256 "$ROOT/../loci/$rel" | awk '{print $1}')"
    if [[ "$actual" != "$expected" ]]; then
      echo "digest mismatch: $rel" >&2
      echo "expected: $expected" >&2
      echo "actual:   $actual" >&2
      exit 1
    fi
  done < "$BUNDLE"
else
  echo "need sha256sum or shasum" >&2
  exit 1
fi

echo "handoff bundle verified"
