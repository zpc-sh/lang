#!/usr/bin/env bash
set -euo pipefail

# Quick tester enrollment
# Generates a short-lived token bundle for a single tester and prints a
# copy/paste block you can send them. No auth for LSP; tokens are for
# identification in harness/MCP only.
#
# Usage:
#   ./scripts/enroll_tester.sh <client_id> [ttl_minutes]
#
# Outputs:
#   - Copy/paste env block for the tester
#   - A local file you can share: /tmp/lang_enroll_<client_id>.env

CLIENT_ID="${1:-}"
TTL_MINUTES="${2:-120}"

if [[ -z "${CLIENT_ID}" ]]; then
  echo "usage: $0 <client_id> [ttl_minutes]" >&2
  exit 1
fi

rand_b64url() {
  # n bytes → base64url (no padding)
  openssl rand -base64 "$1" | tr '+/' '-_' | tr -d '=' | tr -d '\n'
}

timestamp() { date -u +%Y-%m-%dT%H:%M:%SZ; }

EXP_EPOCH=$(( $(date +%s) + (TTL_MINUTES*60) ))
MCP_DEBUG_TOKEN="dbg_$(rand_b64url 24)"
TESTER_API_KEY="ak_$(rand_b64url 24)"
SESSION_TICKET_ID="st_$(rand_b64url 16)"
SESSION_TICKET_SIG="sig_$(rand_b64url 24)"

ENV_PATH="/tmp/lang_enroll_${CLIENT_ID}.env"

cat > "${ENV_PATH}" <<ENV
# ===== LANG Tester Enrollment (generated $(timestamp)) =====
export CLIENT_ID=${CLIENT_ID}
export LSP_HOST=127.0.0.1
export LSP_PORT=4001
export MCP_DEBUG_TOKEN=${MCP_DEBUG_TOKEN}
export TESTER_API_KEY=${TESTER_API_KEY}
export SESSION_DEBUG_TICKET=${SESSION_TICKET_ID}.${EXP_EPOCH}.${SESSION_TICKET_SIG}
# TTL minutes: ${TTL_MINUTES}
ENV

chmod 600 "${ENV_PATH}"

cat <<MSG
================================================================================
LANG Tester Enrollment — ${CLIENT_ID}
================================================================================
Copy/paste the block below into your shell to set up your environment:

source ${ENV_PATH}

Then sanity‑check LSP initialize:

REQ='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":null,"rootUri":null,"capabilities":{},"clientInfo":{"name":"'"${CLIENT_ID}"'","version":"0.1"}}}'; \
LEN=
$(printf "%s" "${REQ}" | wc -c | awk '{print $1}'); \
printf "Content-Length: %s\r\n\r\n%s" "${LEN}" "${REQ}" | nc \
${LSP_HOST:-127.0.0.1} ${LSP_PORT:-4001} | head -c 400

Optional identify notification (after initialize):
printf "Content-Length: %s\r\n\r\n%s" \
  122 \
  '{"jsonrpc":"2.0","method":"lang/tester/identify","params":{"clientId":"'"${CLIENT_ID}"'","token":"'"${MCP_DEBUG_TOKEN}"'"}}' \
  | nc ${LSP_HOST:-127.0.0.1} ${LSP_PORT:-4001}

If you are remote, open an SSH tunnel first:
ssh -N -L 4001:127.0.0.1:4001 <you>@<host>

Files created (share this file only with the intended tester):
  ${ENV_PATH}
================================================================================
MSG

