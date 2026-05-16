## 2026-05-16 - Atom Exhaustion (DoS) via String.to_atom
**Vulnerability:** The application used `String.to_atom/1` to parse service names and keys directly from external proxy requests.
**Learning:** Because atoms are not garbage-collected in the BEAM VM, an attacker can supply random strings in proxy envelopes, exhausting the VM's atom table and causing a total system crash.
**Prevention:** Always use `String.to_existing_atom/1` inside a try/rescue block when parsing user input into atoms. Fallback to an error tuple or keep the string format if the atom doesn't exist.
