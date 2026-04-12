
## 2024-05-24 - [Denial of Service via Atom Table Exhaustion]
**Vulnerability:** Found `String.to_atom/1` being called directly on untrusted background job arguments (e.g., `args["period_type"]`) in Oban workers.
**Learning:** In Elixir, atoms are not garbage collected. Creating atoms dynamically from arbitrary, untrusted input strings allows attackers to slowly or rapidly fill the atom table limit (default 1,048,576), crashing the entire Erlang VM and causing a Denial of Service.
**Prevention:** Always use `String.to_existing_atom/1` for untrusted input. Catch `ArgumentError` to gracefully handle cases where the string isn't an existing atom, providing a default fallback and optionally logging a security warning.
