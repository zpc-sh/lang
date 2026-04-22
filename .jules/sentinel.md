## 2024-05-18 - String.to_atom used on external job arguments in Oban Worker
**Vulnerability:** Found `String.to_atom` being used on Oban job arguments (`args["period_type"]`) in `Lang.Workers.ProductivityMetricsWorker`.
**Learning:** Oban job arguments can be manipulated or constructed externally in a way that allows arbitrary strings to be fed into `String.to_atom`. Elixir atoms are not garbage collected, leading to atom table exhaustion and potentially crashing the VM (Denial of Service).
**Prevention:** Always use `String.to_existing_atom/1` for parsing dynamically provided string values into atoms, especially from job arguments, external requests, or database fields representing enums. Catch the potential `ArgumentError` when doing so.
