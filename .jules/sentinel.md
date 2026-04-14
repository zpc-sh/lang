## 2024-05-30 - Atom Exhaustion Denial of Service
**Vulnerability:** Use of `String.to_atom/1` with unsanitized user input creates an atom for every unique input. Atoms are not garbage collected, leading to atom table exhaustion and application crash (Denial of Service).
**Learning:** Elixir/Erlang atom table is limited (typically 1,048,576). Unsafe atom creation from dynamic sources (like DB, APIs, or job arguments) is a classic DoS vector.
**Prevention:** Always use `String.to_existing_atom/1` when converting untrusted or dynamic strings to atoms, and handle the potential `ArgumentError`.
