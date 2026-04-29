## 2024-05-14 - [Atom Table Exhaustion via Background Job Arguments]
**Vulnerability:** Untrusted input from background job arguments was converted using String.to_atom/1, leading to a potential DoS via atom table exhaustion.
**Learning:** In Elixir, rescue clauses do not support struct pattern matching; error in ArgumentError -> must be used to match exceptions. Also, try blocks must be isolated from broader logic.
**Prevention:** Always use String.to_existing_atom/1 for untrusted input and wrap it in an isolated try/rescue block logging a security warning if it fails.
