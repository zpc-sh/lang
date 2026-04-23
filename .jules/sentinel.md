## 2025-02-18 - Fix Atom Exhaustion DoS in OrchestratorWorker
**Vulnerability:** Untrusted string arguments (like environment names and task names) were converted to atoms using `String.to_atom/1` in the Oban worker. Since the Erlang VM's atom table has a hard limit, an attacker sending many unique strings could exhaust the atom table, crashing the entire node (Denial of Service).
**Learning:** Background workers (like `Lang.Workers.OrchestratorWorker`) often receive external string inputs. Converting these directly using `String.to_atom/1` is a severe risk.
**Prevention:** Always use `String.to_existing_atom/1` (wrapped in a safe `try/rescue` block to handle `ArgumentError`) when converting external or unbounded string inputs to atoms. Return `nil` or safely handle the failure case.
