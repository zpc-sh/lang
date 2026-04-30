## 2026-04-30 - Atom Table Exhaustion in Oban Job Argument Processing
**Vulnerability:** Use of `String.to_atom/1` directly on untrusted inputs (env/task parameters) in `Lang.Workers.OrchestratorWorker` can lead to Denial of Service (DoS) by exhausting the BEAM VM's atom table limits (1,048,576 atoms).
**Learning:** Elixir atoms are never garbage collected. Converting dynamically generated or user-provided strings to atoms using `String.to_atom/1` allows attackers to crash the entire VM.
**Prevention:** Always use `String.to_existing_atom/1` for converting untrusted strings, and catch `ArgumentError` locally with an isolated `try/rescue` block to handle invalid inputs safely while logging a security warning. Do not let the `try/rescue` mask core business logic exceptions.
