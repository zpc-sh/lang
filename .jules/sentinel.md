## 2024-05-15 - Remote Code Execution via Untrusted Atom Creation
**Vulnerability:** Found `apply(String.to_atom(agent_module), :handle_request, ...)` in `Lang.Workers.LSPComparisonWorker` executing dynamically provided untrusted input.
**Learning:** `String.to_atom/1` with arbitrary input exposes the BEAM to Atom Exhaustion DOS and allows calling functions on any loaded module, enabling RCE.
**Prevention:** Always use `String.to_existing_atom/1` for dynamically generated modules or validate the module string prefix securely (e.g., must start with `Elixir.Lang.Testing.Variants.`).
