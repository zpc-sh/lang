# Codex Agent Guardrails (Elixir / Phoenix / Ash)

Keep this short and actionable. Codex-specific codegen rules to avoid common pitfalls.

- Default args: always use `\\`, never `\`. Prefer multi-heads when clearer.
  - Bad: `def run(opts \ [])` (single backslash)
  - Good: `def run(opts \\ [])`; or `def f(x), do: f(x, nil)` / `def f(x,y), do: ...`
- Guards: never call non-guard functions (String/Enum/custom) in guards.
  - Use binary patterns instead of `String.starts_with?/2` in guards.
- Ash macros: import before using `filter/2` with pins.
  - Always `import Ash.Query`; then `resource |> filter(field == ^val) |> Ash.read()`.
- Phoenix.Token TTL: apply on verify, not sign.
  - `sign(endpoint, salt, claims)`; `verify(..., max_age: ttl)`.
- Filesystem: use `Lang.Native.FSScanner` for reads/scans/search, not pure Elixir for large ops.
  - For writes where no NIF exists, use `File.write/3` carefully with error handling.
- Long-running processes: do not emit servers/watchers (e.g., `mix phx.server`). Use tasks that terminate or Oban.
- HTTP client: use `Req` (do not add `httpoison/tesla/httpc`).
- Phoenix 1.8 LiveView: wrap content with `<Layouts.app ...>` and follow imported `<.input>`/`<.icon>` usage.
- Auth routes: ensure `current_scope` is passed; use proper authenticated pipelines per guidelines.
- Env & services: rely on `direnv use_phoenix` module; do not hardcode ports/URLs.
  - Compose lives at repo root. Use Mix tasks: `mix dev.db.up|down|status|wipe`, `mix dev.psql`, `mix dev.redis_cli`.
- Precommit: run `mix precommit` before changes are considered done.
  - Repo enforces a check for single-backslash defaults; Credo custom rule is enabled.

If in doubt, prefer pattern matching, explicit imports, and short-lived Mix tasks.
