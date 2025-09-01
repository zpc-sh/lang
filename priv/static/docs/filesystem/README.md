LANG Filesystem OpenAPI Spec
===========================

This folder contains the generated OpenAPI 3.x spec for the Filesystem Intelligence environment.

How to generate
- Enqueue spec generation: `mix openapi.filesystem`
- Inspect the result: `mix openapi.filesystem.dump`

Output
- JSON: `priv/static/docs/filesystem/openapi.json`

Notes
- Non‑blocking: tasks enqueue Oban jobs and exit.
- Make sure Oban queues are running so the job executes.

