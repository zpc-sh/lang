#!/usr/bin/env bash
set -euo pipefail

# LANG LSP Harness Starter
# - Boots LANG app with LSP TCP server only (no Phoenix)
# - Waits for port 4001, performs LSP initialize sanity check
# - Keeps BEAM alive for a limited duration, then exits cleanly

PORT="${LSP_PORT:-4001}"
DURATION_SEC="${LSP_DURATION_SECONDS:-1800}"   # default 30 minutes
WAIT_TIMEOUT_SEC="${LSP_WAIT_TIMEOUT_SECONDS:-15}"

echo "[LSP] Starting on 127.0.0.1:${PORT} for ${DURATION_SEC}s..."

# Launch LSP-only BEAM (no Phoenix), time-limited, on loopback port
LSP_PORT="${PORT}" mix run -e 'Application.ensure_all_started(:lang); :timer.sleep(String.to_integer(System.get_env("LSP_DURATION_SECONDS") || "1800") * 1000)' \
  >/tmp/lang_lsp.out 2>/tmp/lang_lsp.err &
LSP_PID=$!
trap 'echo "[LSP] Stopping (pid ${LSP_PID})"; kill ${LSP_PID} >/dev/null 2>&1 || true' EXIT

# Wait for port to listen (nc or bash /dev/tcp fallback)
echo -n "[LSP] Waiting for TCP ${PORT}..."
deadline=$((SECONDS + WAIT_TIMEOUT_SEC))
until (command -v nc >/dev/null && nc -z 127.0.0.1 "${PORT}") || { exec 3<>/dev/tcp/127.0.0.1/"${PORT}" 2>/dev/null && exec 3>&- 3<&-; }; do
  if (( SECONDS >= deadline )); then
    echo; echo "[LSP] Port did not open in ${WAIT_TIMEOUT_SEC}s. See /tmp/lang_lsp.err"; exit 1
  fi
  sleep 0.2
done
echo " up."

# Build and send minimal LSP initialize over TCP (sanity check)
REQ_BODY='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":null,"rootUri":null,"capabilities":{},"clientInfo":{"name":"harness","version":"0.1"}}}'
LEN=$(printf "%s" "${REQ_BODY}" | wc -c | awk '{print $1}')
printf "Content-Length: %s\r\n\r\n%s" "${LEN}" "${REQ_BODY}" > /tmp/lsp_init.req

echo "[LSP] Sending initialize; showing first response bytes:"
if command -v nc >/dev/null; then
  (cat /tmp/lsp_init.req; sleep 0.2) | nc 127.0.0.1 "${PORT}" | head -c 400 || true
else
  # Fallback using bash /dev/tcp (no read possible); at least sends the request
  exec 3<>/dev/tcp/127.0.0.1/"${PORT}"
  cat /tmp/lsp_init.req >&3
  exec 3>&- 3<&-
  echo "[LSP] (fallback) initialize sent; install 'nc' for response preview"
fi
echo
echo "[LSP] Ready. Point your agent’s LSP client at 127.0.0.1:${PORT}"
echo "[LSP] Logs: /tmp/lang_lsp.out (stdout), /tmp/lang_lsp.err (stderr)"
echo "[LSP] Press Ctrl+C to stop (or will exit after ${DURATION_SEC}s)."

wait ${LSP_PID}

