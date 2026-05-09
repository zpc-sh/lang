## 2024-05-09 - Dynamic Module Dispatch RCE and DoS
**Vulnerability:** Untrusted input from Oban job arguments (`agent_variant["provider_module"]`) was converted to an atom using `String.to_atom/1` and used in `apply/3` for dynamic dispatch without validation, leading to Remote Code Execution (RCE) and Atom Table Exhaustion (DoS).
**Learning:** Direct dispatch on dynamically provided strings bypasses module encapsulation. The `String.to_atom/1` function does not garbage collect, leading to memory exhaustion if fed arbitrary input.
**Prevention:** Always validate that dynamic module names start with a permitted namespace prefix (e.g., `Elixir.Lang.Testing.Variants.`) before dispatching, and always use `String.to_existing_atom/1` with proper exception handling to prevent DoS.
