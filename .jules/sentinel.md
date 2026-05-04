## 2024-05-04 - Fix Denial of Service via Atom Exhaustion
**Vulnerability:** Found `String.to_atom/1` used on untrusted string inputs (Oban job arguments) in `lib/lang/workers/productivity_metrics_worker.ex`. Because atoms in Erlang/Elixir are not garbage collected, this could allow an attacker to exhaust the atom table memory limits, causing a system crash (Denial of Service).
**Learning:** Untrusted string input originating from job payloads was improperly converted to atoms instead of safely matching existing atoms.
**Prevention:** Always use `String.to_existing_atom/1` wrapped in a `try/rescue` block to handle potential `ArgumentError` when dealing with dynamically generated or untrusted string inputs.
