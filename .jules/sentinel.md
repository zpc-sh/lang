## 2024-05-18 - [Prevent Atom Exhaustion in Oban Workers]
**Vulnerability:** Untrusted string input from background job arguments was being converted to atoms using `String.to_atom/1`, which can lead to atom exhaustion (Denial of Service) since atoms are not garbage collected in Elixir.
**Learning:** Oban workers receive JSON arguments (strings) and Elixir code frequently expects atoms for keywords or internal matching. Developers often blindly convert with `String.to_atom/1`.
**Prevention:** Always use `String.to_existing_atom/1` with a `try/rescue` fallback pattern when dealing with job arguments or external inputs that must be cast to atoms.
