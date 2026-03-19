LANG Systems OpenAPI Spec
========================

This folder contains the generated OpenAPI 3.x spec for the Systems Intelligence environment.

How to generate
- Enqueue spec generation: `mix openapi.systems`
- Inspect the result: `mix openapi.systems.dump`

Output
- JSON: `priv/static/docs/systems/openapi.json`

Notes
- Enqueues an Oban job and exits; no long‑running server.
- Make sure Oban queues are running for job execution.

