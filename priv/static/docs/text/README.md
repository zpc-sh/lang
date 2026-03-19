LANG Text OpenAPI Spec
======================

This folder contains the generated OpenAPI 3.x spec for the Text Intelligence environment.

How to generate
- Enqueue spec generation: `mix openapi.text`
  - Boots the app, enqueues an Oban job, and exits.
- Inspect the result: `mix openapi.text.dump`
  - Prints spec path and endpoint/schema counts; rerun after the job completes if needed.

Output
- JSON: `priv/static/docs/text/openapi.json`

Notes
- Do not start long‑running servers (e.g., `mix phx.server`).
- Jobs run in Oban with retries. Ensure Oban queues are active in your environment.

