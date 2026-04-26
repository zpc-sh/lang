## 2025-01-20 - Prevent Atom Table Exhaustion DoS in Workers
**Vulnerability:** Converting unsanitized user inputs or job arguments to atoms using `String.to_atom/1` can lead to atom table exhaustion Denial of Service (DoS) attacks, as atoms are not garbage collected in Elixir.
**Learning:** `Oban.Job` arguments or incoming API payloads that are strings should never be dynamically converted to atoms without checks, as malicious payloads with uniquely generated strings could crash the node.
**Prevention:** Always use `String.to_existing_atom/1` when converting dynamic strings to atoms. Wrap the call in a `try/rescue` block targeting `ArgumentError` to safely catch invalid values, log a security warning, and gracefully fallback to a safe default value.
