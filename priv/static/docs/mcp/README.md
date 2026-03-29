LANG MCP OpenAPI Spec
======================

This folder contains the generated OpenAPI 3.1 spec for the MCP (Model Context Protocol) Broker endpoints.

How to generate
- Enqueue spec generation: `mix openapi.mcp`
  - This starts the app (including Oban) and enqueues a job that writes the spec to `priv/static/docs/mcp/openapi.json`.
- Inspect the result: `mix openapi.mcp.dump`
  - Prints the spec path and endpoint counts. If the file isn’t found yet, wait a moment for the job to complete and run again.

Output
- JSON: `priv/static/docs/mcp/openapi.json`

Notes
- Do not start long‑running servers (e.g., `mix phx.server`) for this. The mix task boots the app briefly, enqueues the job, and exits.
- Generation runs inside an Oban worker (`Lang.Workers.MCPEnvironment`) and is retried on failure.
- If you are running in an environment without Oban queues, the job may not execute. In that case, run your application normally with Oban enabled and then run `mix openapi.mcp`.

