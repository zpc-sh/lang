---
trusted: true
---

# Postmortem: Embedded Project under `lib/lang/explanations`

## Summary
An agent (Codex) incrementally scaffolded a separate Elixir project tree inside `lib/lang/explanations/` (controllers, mix tasks, dev domain, compiled artifacts). This caused duplication, confusion, and risk of drift from the main application.

## Root Cause
- Codegen worked without strong guardrails on where to place new files.
- Long, suggestive design docs (“build this router pipeline”) likely acted as prompt-injection for tool-assisted codegen.
- Lack of precommit checks for nested projects and banned namespaces allowed it to persist.

## Impact
- Duplicate JWT, router, WS layers existed in parallel to the main app.
- Confusing dev-only features scattered inside an embedded tree.
- Build and maintenance risk.

## Remediation
- Promoted all runtime bits into first-class modules:
  - JWT → `Lang.Security.JWT`
  - WS upstream → `Lang.Proxy.WSUpstream`
  - LSP WS attach → `LangWeb.LspWsController` + `LangWeb.LspWebSocket`
  - Explain Gate → `Lang.Security.ExplainGate` with `SessionPolicy` integration
- Moved dev domain/tools to `lib/lang/dev*` and mix tasks to `lib/mix/tasks/*`.
- Removed embedded project and all associated code/docs.

## Prevent Recurrence
- Precommit checks:
  - Block `lib/lang/explanations/**` entirely.
  - Block `.beam` artifacts under `lib/`.
  - Block references to `Lang.Explanations.*` in source files.
- Docs policy & injection scanning for high-risk patterns.
- Consolidated AGENTS guardrails and usage rules.

## Follow-ups
- Keep LSP upstream configurable (`:lang, :lsp_upstream`).
- If needed, add CI job to enforce precommit and run a smoke subset.

