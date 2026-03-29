LANG OpenAPI Artifacts
======================

This directory contains generated OpenAPI specs for multiple environments.

Specs
- MCP: `priv/static/docs/mcp/openapi.json`
  - Generate: `mix openapi.mcp`
  - Inspect: `mix openapi.mcp.dump`
- Text: `priv/static/docs/text/openapi.json`
  - Generate: `mix openapi.text`
  - Inspect: `mix openapi.text.dump`
- Filesystem: `priv/static/docs/filesystem/openapi.json`
  - Generate: `mix openapi.filesystem`
  - Inspect: `mix openapi.filesystem.dump`
- Cloud: `priv/static/docs/cloud/openapi.json`
  - Generate: `mix openapi.cloud`
  - Inspect: `mix openapi.cloud.dump`
- Systems: `priv/static/docs/systems/openapi.json`
  - Generate: `mix openapi.systems`
  - Inspect: `mix openapi.systems.dump`

All-at-once
- Enqueue all env specs: `mix openapi.all`

Notes
- All tasks enqueue Oban jobs and exit; ensure Oban queues are running.
- Do not run long‑lived servers for generation.

