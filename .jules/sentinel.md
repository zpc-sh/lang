## 2024-05-14 - Fix RCE and Atom exhaustion vulnerabilities in LSPComparisonWorker
**Vulnerability:** The code read an arbitrary string from user input (`agent_module`) and converted it to an atom via `String.to_atom`, leading to potential Atom Exhaustion (DoS). It also used the atom in `apply/3`, leading to a potential Remote Code Execution (RCE) vulnerability.
**Learning:** We need to validate dynamic module dispatcher targets to prevent RCE.
**Prevention:** Use `String.starts_with?/2` to validate the namespace of dynamically requested modules to ensure execution is safe, and use `String.to_existing_atom/1` in a `try/rescue` block to prevent atom exhaustion.
