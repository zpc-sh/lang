#!/usr/bin/env bash
set -euo pipefail

# Build a Dialyzer PLT for the current environment using dialyxir config.
# Stores PLT at _build/$MIX_ENV/dialyzer.plt

export MIX_ENV="${MIX_ENV:-dev}"
echo "[dialyzer] Building PLT for MIX_ENV=${MIX_ENV}…"

mix deps.get >/dev/null
mix compile >/dev/null

# Build PLT (dialyxir will create or update the PLT as configured in mix.exs)
mix dialyzer --plt

echo "[dialyzer] Done. PLT: _build/${MIX_ENV}/dialyzer.plt"

