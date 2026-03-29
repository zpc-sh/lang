# Containerized Test Agents (LSP)

Run 5 simple LSP clients in containers against your host loopback LSP at 127.0.0.1:4001.

## Prep on host

1) Start LSP (loopback, no auth):

```bash
LSP_PORT=4001 LSP_DURATION_SECONDS=1800 ./scripts/lsp_harness.sh
```

2) Generate 5 tester bundles:

```bash
./scripts/gen_tester_tokens_batch.sh 5
# Note the output directory, e.g.: /tmp/lang_lsp_testers_20250828_130102
export TEST_ENV_DIR=/tmp/lang_lsp_testers_20250828_130102
```

## Build and run agents

```bash
docker compose -f containers/agents/docker-compose.yml build
docker compose -f containers/agents/docker-compose.yml up
```

Each agent prints: connect → initialize → completion → done. They target `host.docker.internal:4001`.

Notes
- macOS/Windows: `host.docker.internal` works by default.
- Linux: Docker 20.10+ required for `host-gateway` mapping; otherwise consider `--network host` (Linux only) or SSH tunnels.
- Tokens identify clients in your harness/MCP logs; LSP TCP itself is unauthenticated.

