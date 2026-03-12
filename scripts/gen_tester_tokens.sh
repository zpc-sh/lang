#!/usr/bin/env bash
set -euo pipefail

# LANG — Tester Token Generator
# Generates ephemeral tokens/keys for local testers and prints export lines.
# No persistence, no auth checks. Intended for loopback/dev only.

rand_b64url() {
  # n bytes → base64url (no padding)
  openssl rand -base64 "$1" | tr '+/' '-_' | tr -d '=' | tr -d '\n'
}

timestamp() { date -u +%Y-%m-%dT%H:%M:%SZ; }

TTL_MINUTES="${TTL_MINUTES:-120}"
EXP_EPOCH=$(( $(date +%s) + (TTL_MINUTES*60) ))

MCP_DEBUG_TOKEN="dbg_$(rand_b64url 24)"
TESTER_API_KEY="ak_$(rand_b64url 24)"
SESSION_TICKET_ID="st_$(rand_b64url 16)"
SESSION_TICKET_SIG="sig_$(rand_b64url 24)"

cat <<ENV
# ===== LANG Tester Tokens (generated $(timestamp)) =====
export MCP_DEBUG_TOKEN=${MCP_DEBUG_TOKEN}
export TESTER_API_KEY=${TESTER_API_KEY}
export SESSION_DEBUG_TICKET=${SESSION_TICKET_ID}.${EXP_EPOCH}.${SESSION_TICKET_SIG}
# TTL minutes: ${TTL_MINUTES}
ENV

echo
echo "Usage hints:"
echo "  # MCP bridge (if enabled): require X-Debug-Token: \"\$MCP_DEBUG_TOKEN\" or Authorization: Bearer \"\$MCP_DEBUG_TOKEN\""
echo "  # Test harness scripts can read TESTER_API_KEY for gating or simple headers"
echo "  # SESSION_DEBUG_TICKET may be used for short-lived session connects in local experiments"

