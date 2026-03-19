#!/usr/bin/env bash
set -euo pipefail

# LANG — Batch Tester Token Generator
# Usage: ./scripts/gen_tester_tokens_batch.sh [COUNT]
# Generates COUNT (default 5) tester token bundles under /tmp and prints a summary.

COUNT="${1:-5}"
TTL_MINUTES="${TTL_MINUTES:-120}"

rand_b64url() {
  # n bytes → base64url (no padding)
  openssl rand -base64 "$1" | tr '+/' '-_' | tr -d '=' | tr -d '\n'
}

timestamp() { date -u +%Y-%m-%dT%H:%M:%SZ; }

STAMP=$(date +%Y%m%d_%H%M%S)
BASE_DIR="/tmp/lang_lsp_testers_${STAMP}"
mkdir -p "${BASE_DIR}"

EXP_EPOCH=$(( $(date +%s) + (TTL_MINUTES*60) ))

echo "[TOKENS] Generating ${COUNT} tester bundles (TTL ${TTL_MINUTES}m) in ${BASE_DIR}"

for i in $(seq 1 "${COUNT}"); do
  CLIENT_ID="client-${i}"
  MCP_DEBUG_TOKEN="dbg_$(rand_b64url 24)"
  TESTER_API_KEY="ak_$(rand_b64url 24)"
  SESSION_TICKET_ID="st_$(rand_b64url 16)"
  SESSION_TICKET_SIG="sig_$(rand_b64url 24)"

  FILE="${BASE_DIR}/${CLIENT_ID}.env"
  cat > "${FILE}" <<ENV
# ===== LANG Tester Tokens (generated $(timestamp)) =====
export CLIENT_ID=${CLIENT_ID}
export MCP_DEBUG_TOKEN=${MCP_DEBUG_TOKEN}
export TESTER_API_KEY=${TESTER_API_KEY}
export SESSION_DEBUG_TICKET=${SESSION_TICKET_ID}.${EXP_EPOCH}.${SESSION_TICKET_SIG}
# TTL minutes: ${TTL_MINUTES}
ENV
  chmod 600 "${FILE}"
done

echo
echo "[TOKENS] Done. Distribute the following files to testers (do NOT commit):"
for i in $(seq 1 "${COUNT}"); do
  echo "  - ${BASE_DIR}/client-${i}.env"
done

echo
echo "Usage (per tester):"
echo "  source /path/to/client-N.env" 
echo "  # LSP is unauthenticated TCP on 127.0.0.1:4001; tokens are for harness/MCP identification"
echo "  # Optional: send a custom LSP notification after initialize to identify:"
echo "  #   method: \"lang/tester/identify\", params: { token: \"\$MCP_DEBUG_TOKEN\", clientId: \"\$CLIENT_ID\" }"

