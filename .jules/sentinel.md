## 2024-05-24 - Atom Table Exhaustion in Oban Workers
**Vulnerability:** Found `String.to_atom/1` used to parse untrusted Job arguments (`args["period_type"]`, `args["granularity"]`) in `Lang.Workers.ProductivityMetricsWorker` and `Lang.Workers.BillingAggregateUsageWorker`.
**Learning:** Elixir's atom table is not garbage-collected, and dynamically generating atoms from user-provided or external inputs can quickly lead to memory exhaustion and a Denial of Service (DoS) crash.
**Prevention:** Always use `String.to_existing_atom/1` for untrusted string inputs, wrapping the call in a `try/rescue` block targeting `ArgumentError` to safely fallback or reject invalid data.
