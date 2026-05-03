## 2026-05-03 - Denial of Service via Atom Exhaustion in Worker Arguments
**Vulnerability:** Untrusted string input from `Oban.Job` args (`args["period_type"]`) was passed directly to `String.to_atom/1` in `Lang.Workers.ProductivityMetricsWorker`.
**Learning:** `String.to_atom/1` does not garbage collect the atoms it creates. Converting arbitrary or untrusted user input directly to atoms can exhaust the Erlang VM's atom table limit (default 1,048,576), crashing the entire node.
**Prevention:** Always use `String.to_existing_atom/1` for untrusted input. Catch the `ArgumentError` in an isolated `try/rescue` block to handle invalid inputs safely without crashing the node.
