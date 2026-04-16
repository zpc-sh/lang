## 2025-03-04 - [Prevent Atom Exhaustion DoS in Background Workers]
**Vulnerability:** Untrusted external inputs from Oban background job arguments were being dynamically converted to atoms using `String.to_atom/1`.
**Learning:** Atoms are not garbage collected in Elixir/Erlang. Processing external strings via `String.to_atom/1` exposes the application to atom table exhaustion, ultimately causing an uncontrollable VM crash.
**Prevention:** Consistently use `String.to_existing_atom/1` inside `try/rescue` blocks for any dynamic input conversion, returning safe default atoms for `ArgumentError`s and logging the attempts.
