## 2024-04-28 - Atom Exhaustion DoS Mitigation
**Vulnerability:** Unbounded conversion of user-controlled strings (like job arguments) to atoms using `String.to_atom/1` can exhaust the BEAM atom table and crash the application.
**Learning:** Always use `String.to_existing_atom/1` when converting external input to atoms, as it only succeeds if the atom already exists in the system.
**Prevention:** Use `String.to_existing_atom/1` and handle potential `ArgumentError` gracefully to prevent DoS attacks via atom exhaustion.
