# Usage Rules

This folder contains synced usage rules for dependencies (via `mix dev.usage_rules.sync`).

- Aggregate links: `USAGE_RULES.md`
- Do not inline large rule sets into AGENTS docs to keep agent prompts lean.
- Update rules locally with:

  mix dev.usage_rules.sync --all

or sync a specific subset:

  mix dev.usage_rules.sync ash ash_postgres

