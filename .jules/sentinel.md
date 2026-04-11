## 2024-04-11 - [Atom Table Exhaustion DoS in Worker Arguments]
**Vulnerability:** Untrusted string input from background job arguments (`args["period_type"]`) was passed directly to `String.to_atom/1`.
**Learning:** Background jobs often deserialize JSON payloads where keys/values are strings. Converting these unvalidated strings to atoms without checking can lead to atom table exhaustion and crash the Erlang VM.
**Prevention:** Always use `String.to_existing_atom/1` when parsing external or untrusted strings into atoms, and use a try/rescue block to handle `ArgumentError` gracefully with safe fallbacks and security warning logs.
