# Lang Polyglot (Internal)

Polyglot provides internal helpers to analyze and transform markdown that embeds structured data and artifacts.

Scope (non-exhaustive):
- Format detection for common infrastructure‑as‑text patterns (e.g., dockerfile, k8s yaml)
- Metadata extraction from fenced code and comments
- Building a normalized artifact set for downstream tools

Notes
- This module is intended for internal use. It does not expose public execution facilities.
- Any runtime actions are decoupled into controlled services and are not part of this package’s public surface.

Status
- Core parsing and artifact extraction are available for internal callers.

For questions, contact the LANG team.
```
