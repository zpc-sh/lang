# Explanations Rendering (JSON‑LD → Ash) — Plan & Guardrails

This plan aligns JSON‑LD–driven codegen of “Explanations” resources with current repo guardrails and shows how to integrate results across the codebase without breaking precommit rules.

## Current Guardrail (Important)

- Precommit explicitly blocks the path and namespace:
  - Paths: `lib/lang/explanations/**`
  - Namespace: `Lang.Explanations.*`
- Rationale: See `docs/legacy/postmortems/codex-embedded-project.md` — a previous agent generated a mini‑app under `lib/lang/explanations/`, causing drift. The tree was removed and the namespace/path are banned.

If you truly require `lib/lang/explanations/**`, we must first lift/update the guardrail in `lib/mix/tasks/precommit.ex`. Otherwise, use an alternate, allowed namespace/path (recommended).

## Recommendation (Safe Default)

- Target path: `lib/lang/semantic/explanations/` (new)
- Namespace root: `Lang.Semantic.Explanations`
- Benefit: Aligned with guardrails, avoids banned path/namespace, integrates cleanly with Ash + Phoenix.

If you later decide to restore `lib/lang/explanations/**`, apply a small change to `precommit` (not done here) and update the namespace checks.

## JSON‑LD → Ash Codegen Mapping

- Input: JSON‑LD files (or manifests) that define Explanations domain types.
- Module naming: `@type` or profile name → `Lang.Semantic.Explanations.<CamelCase>`
- Attributes: JSON‑LD properties → `Ash.Resource` attributes with types inferred from example values or `@context` hints
- Relationships: nested objects/ids → `belongs_to`, `has_many`, `many_to_many`
- Actions:
  - `:create`, `:update`, `:destroy`
  - `:read` with filters/sorts; `:by_id` read action helper
- Data layer: `AshPostgres` (if persisted) or `Ash.Resource` with `:embedded?` true for in‑memory resources
- Validation: generate changesets from JSON‑LD `@context` constraints when available

## File Layout (recommended)

```
lib/
  lang/
    semantic/
      explanations/
        resource_registry.ex        # runtime registry of generated modules
        types.ex                    # shared types/enums
        explanation.ex              # example Ash resource
        explanation_link.ex         # example relation
```

## Integration Points

- LSP
  - Handlers produce/consume these resources (e.g., `lang.explanations.create`, `lang.explanations.read`) via `Lang.LSP.Handlers.*`
  - Debug harness already in place: `mix lsp.debug`, `mix lsp.debug.session` (plan‑based)
- Web/UI
  - Controllers/LiveViews use Ash queries via `Lang.Semantic.Explanations.*`
  - Respect Phoenix v1.8 rules (Layouts.app wrapper, Auth pipelines, etc.)
- Storage/Folder
  - JSON‑LD sources can come from OCI (AI Memory). Use TOC to resolve paths, then render to Ash resources
  - Keep generation idempotent; link back via annotations (owner/workspace, layerType)

## JSON‑LD Render Pipeline (high‑level)

1. Source JSON‑LD (local or `oci://owner/repo@ref` via Folder adapter)
2. Normalize using `@context` and profiles (see `docs/FOLDER_API_SYNC.jsonld`)
3. Map to Ash schema (attributes/relations/actions)
4. Generate modules to `lib/lang/semantic/explanations/`
5. Register modules in `resource_registry.ex` for discovery

## Example Resource (sketch)

```elixir
# lib/lang/semantic/explanations/explanation.ex
defmodule Lang.Semantic.Explanations.Explanation do
  use Ash.Resource, data_layer: AshPostgres.DataLayer

  postgres do
    table "explanations"
    repo Lang.Repo
  end

  attributes do
    uuid_primary_key :id
    attribute :title, :string, allow_nil?: false
    attribute :content, :string
    attribute :tags, {:array, :string}, default: []
    attribute :lang, :string, default: "en"
  end

  actions do
    defaults [:read, :create, :update, :destroy]
    read :by_id do
      argument :id, :uuid, allow_nil?: false
      get? true
      filter expr(id == ^arg(:id))
    end
  end
end
```

## What if we must use `lib/lang/explanations/**`?

- Requires explicit approval to lift guardrails:
  - Remove/adjust patterns in `lib/mix/tasks/precommit.ex` that block the path/namespace
  - Update any CI/automation that enforces those checks
- Then re‑target codegen to `lib/lang/explanations/` and namespace `Lang.Explanations.*`

## Next Steps (choose one)

- Proceed with safe target: I’ll scaffold `lib/lang/semantic/explanations/` and a tiny codegen Mix task to render from a JSON‑LD file.
- Or approve a guardrail change: I’ll open a focused patch to precommit to allow `lib/lang/explanations/**` and `Lang.Explanations.*`, then scaffold there.

## Debug & Diagnostics (already available)

- Client harness: `mix lsp.debug --explain` (prints human explanations per call)
- Plan runner: `mix lsp.debug.session --plan scripts/lsp_debug_plan.sample.json` (pass/fail summary)
- Server logs: `LSP_DEBUG_LOG=/tmp/lsp_debug.jsonl`
- Telemetry & rollups: `LSP_METRICS_LOG=/tmp/lsp_metrics.jsonl` with optional `LSP_METRICS_FLUSH_MS`

```bash
export LSP_DEBUG_LOG=/tmp/lsp_debug.jsonl
export LSP_METRICS_LOG=/tmp/lsp_metrics.jsonl
mix lsp.smoke --port 4001 --duration 60
mix lsp.debug --explain
```

---

This plan keeps us compliant today and flexible for later if you choose to restore the original path/namespace.
