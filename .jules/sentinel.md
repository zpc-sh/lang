## 2024-05-24 - [Atom Table Exhaustion (Denial of Service)]
**Vulnerability:** Found `String.to_atom/1` used on untrusted user input directly in background Oban workers (e.g., `Lang.Workers.OrchestratorWorker` and `Lang.Workers.ProductivityMetricsWorker`).
**Learning:** `String.to_atom/1` creates a new atom that is never garbage collected, meaning attackers can send randomized strings to these endpoints/jobs to exhaust the beam's atom table and crash the application.
**Prevention:** Never use `String.to_atom/1` on strings derived from user input or job arguments. Use a safer mechanism: try to convert via `String.to_existing_atom/1` inside a `try/rescue` block that captures `ArgumentError` and safely falls back (or logs a security warning) rather than continuing business logic.
