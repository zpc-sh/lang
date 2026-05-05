## 2024-05-15 - Atom Table Exhaustion DoS Prevention
**Vulnerability:** Untrusted Oban job arguments were being converted to atoms using `String.to_atom/1`, leading to a potential Denial of Service (DoS) vulnerability via atom table exhaustion.
**Learning:** In Elixir/Erlang, dynamically created atoms are not garbage collected. Converting arbitrary user input or job arguments to atoms can crash the BEAM VM if the maximum atom limit is exceeded.
**Prevention:** Always use `String.to_existing_atom/1` (and handle `ArgumentError`) or explicit string pattern matching when converting dynamic or untrusted strings to atoms.
