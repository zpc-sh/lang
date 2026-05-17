## 2025-05-17 - Fix Remote Code Execution and Atom Exhaustion in LSP Comparison Worker

**Vulnerability:**
The application used `apply(String.to_atom(agent_module), :handle_request, ...)` with an untrusted, dynamically provided string `agent_module` from the database/user input (`agent_variant["provider_module"]`). This created two critical vulnerabilities:
1. **Atom Exhaustion (DoS):** Using `String.to_atom/1` on unvalidated dynamic input allows an attacker to repeatedly supply unique strings. Since atoms are not garbage collected in the BEAM VM, this eventually crashes the application by exceeding the maximum atom limit (1,048,576 by default).
2. **Remote Code Execution (RCE):** The `apply/3` call allowed execution of arbitrary modules via `handle_request/3`. If an attacker successfully created or discovered a module that implements this function in a dangerous way, they could gain control over the system.

**Learning:**
Functions dynamically determining which module to call based on external input (especially in job queues or request handlers) must rigorously validate the input. Elixir developers often overlook that `String.to_atom/1` retains atoms indefinitely, and that dynamic dispatch (`apply/3`) with user input bypasses compile-time checks, leading to severe RCE if untrusted strings are cast to atoms and invoked.

**Prevention:**
- Always enforce an explicit whitelist or namespace validation (e.g., `String.starts_with?(input, "Elixir.Lang.Testing.Variants.")`) for module strings used in dynamic dispatch.
- Always use `String.to_existing_atom/1` inside an isolated `try/rescue` block targeting `ArgumentError` when converting dynamic strings to module names to prevent Atom Exhaustion DoS.
