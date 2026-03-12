#!/usr/bin/env bash
set -euo pipefail

# Captures LSP TCP traffic on loopback port 4001 into a rotating PCAP.
# Requires tcpdump (preferred) or tshark.

PORT="${LSP_PORT:-4001}"
OUT_DIR="${LSP_PCAP_DIR:-/tmp}"
ROTATE_MB="${LSP_PCAP_ROTATE_MB:-10}"
ROTATE_COUNT="${LSP_PCAP_ROTATE_COUNT:-5}"

mkdir -p "${OUT_DIR}"
STAMP=$(date +%Y%m%d_%H%M%S)
PCAP_PREFIX="${OUT_DIR}/lsp_${PORT}_${STAMP}"

if command -v tcpdump >/dev/null; then
  echo "[PCAP] Using tcpdump; writing ${ROTATE_COUNT} files x ${ROTATE_MB}MB: ${PCAP_PREFIX}_NNN.pcap"
  # -i lo for Linux; on macOS loopback is lo0
  IFACE="lo"
  if [[ "$(uname)" == "Darwin" ]]; then IFACE="lo0"; fi
  sudo tcpdump -i "${IFACE}" -s 0 -w "${PCAP_PREFIX}.pcap" 'tcp and port '"${PORT}" \
    -C "${ROTATE_MB}" -W "${ROTATE_COUNT}"
elif command -v tshark >/dev/null; then
  echo "[PCAP] Using tshark; writing ring buffer to ${PCAP_PREFIX}_NNN.pcap"
  IFACE="lo"
  if [[ "$(uname)" == "Darwin" ]]; then IFACE="lo0"; fi
  sudo tshark -i "${IFACE}" -f "tcp port ${PORT}" -b filesize:"$((ROTATE_MB*1024))" -b files:"${ROTATE_COUNT}" -w "${PCAP_PREFIX}.pcap"
else
  echo "[PCAP] Neither tcpdump nor tshark found. Please install one of them." >&2
  exit 1
fi

