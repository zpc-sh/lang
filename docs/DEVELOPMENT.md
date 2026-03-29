# Development Guide

## Prerequisites

- direnv (with `~/.config/direnv/lib/use_phoenix.sh` installed)
- Docker with `docker compose`
- PostgreSQL client (`psql`) and Redis CLI (`redis-cli`)
- Elixir/Mix

## Environment Setup

1) In project `.envrc`, load the reusable module and any overrides:

```
use mise

# Optional overrides
export DB_USERNAME=postgres
export DB_PASSWORD=postgres
export DB_HOSTNAME=localhost
export DB_DATABASE=lang_dev
export PG_HEALTHCHECK=1
export PG_HEALTHCHECK_ATTEMPTS=3
export PG_HEALTHCHECK_DELAY=0.5
# Redis (optional)
export REDIS_HOSTNAME=localhost
# export REDIS_PASSWORD=

use phoenix
```

2) Allow and reload direnv:

```
direnv allow
direnv reload
```

The module sets `DB_PORT`, `PHX_PORT`, `PORT`, `DATABASE_URL`, `REDIS_PORT`, `REDIS_URL`, picking free ports if defaults are busy.

## Local Services

Use Mix tasks (thin wrappers around `docker compose`). They run and exit (no long-running processes):

- Start: `mix dev.db.up`
- Status: `mix dev.db.status`
- Stop (keep volumes): `mix dev.db.down`
- Wipe (remove volumes): `mix dev.db.wipe`
- Restart: `mix dev.db.restart`

Helpers:
- PostgreSQL: `mix dev.psql` or `mix dev.psql --query "select now();"`
- Redis: `mix dev.redis_cli`

Compose file: `docker-compose.yml` at project root, parameterized via environment variables.

## Project Structure

- `examples/`: demo and one-off scripts for manual testing
- `docs/`: documentation, guides, and specs (this file)
- `work/logs/`: local logs and crash dumps

## Conventions

- Do not start long-running commands from scripts (e.g. `mix phx.server`). Use tasks that terminate.
- Run `mix precommit` before committing changes.
- Use Ash resources for data, Rust NIFs for FS/analysis, Oban for long jobs.

