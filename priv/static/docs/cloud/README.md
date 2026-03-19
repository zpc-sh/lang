LANG Cloud OpenAPI Spec
======================

This folder contains the generated OpenAPI 3.x spec for the Cloud Intelligence environment.

How to generate
- Enqueue spec generation: `mix openapi.cloud`
- Inspect the result: `mix openapi.cloud.dump`

Output
- JSON: `priv/static/docs/cloud/openapi.json`

Notes
- Uses Oban to generate asynchronously; no long‑running processes are started.
- Ensure Oban queues are active so the job can run.

