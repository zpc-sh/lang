## 2024-05-15 - DoS via Atom Table Exhaustion
**Vulnerability:** Untrusted user input was converted to atoms using `String.to_atom` in `lib/lang/workers/lsp_comparison_worker.ex`, potentially leading to Denial of Service (DoS) due to atom table exhaustion.
**Learning:** `String.to_atom` creates atoms dynamically, and since atoms are not garbage collected in Erlang/Elixir, providing an unbounded amount of dynamic string inputs could cause the BEAM node to crash when the atom table limit is reached.
**Prevention:** Always use `String.to_existing_atom` when dealing with user input. If an atom should exist but doesn't, it indicates an invalid input, and the resulting `ArgumentError` should be handled appropriately (e.g., returning an error or logging the incident).
