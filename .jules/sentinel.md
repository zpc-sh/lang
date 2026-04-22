## 2024-04-22 - [Security] Prevent Atom Table Exhaustion in Workers
**Vulnerability:** Untrusted external inputs for environments and tasks in background jobs were being dynamically converted to atoms using String.to_atom/1. Since the BEAM VM atom table is limited and not garbage collected, malicious inputs could crash the application by filling the table.
**Learning:** Elixir background jobs (Oban) accepting external string parameters must be especially careful when converting them to symbols used for function dispatching or queue naming.
**Prevention:** Always use String.to_existing_atom/1 wrapped in an isolated try/rescue block when parsing dynamically-supplied system environment or task parameters, rather than String.to_atom/1.
