## 2024-05-24 - Do not use String.to_atom on user input
**Vulnerability:** Converting untrusted input strings to atoms using `String.to_atom/1` can exhaust the BEAM atom table, leading to Denial of Service (DoS).
**Learning:** `agent_module` is derived from an untrusted source (agent_variant["provider_module"]). Dynamic function dispatch (`apply/3`) using user input is also a critical Remote Code Execution (RCE) vector.
**Prevention:** Always use `String.to_existing_atom/1` when converting strings to atoms if the string is expected to match a known entity. Furthermore, validate `agent_module` against an explicit allowlist before calling `apply/3`.
