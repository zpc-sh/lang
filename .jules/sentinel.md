## 2025-04-07 - [Atom Table Exhaustion in Workers]
**Vulnerability:** Untrusted external arguments from Oban jobs (`period_type`) were parsed using `String.to_atom/1`, leading to potential atom table exhaustion and Denial of Service (DoS).
**Learning:** Elixir atoms are not garbage collected. Using `String.to_atom/1` on arbitrary external input (like JSON arguments mapped to background workers) creates a vector to crash the VM by exceeding the atom limit.
**Prevention:** Always use `String.to_existing_atom/1` for untrusted input conversions, properly catching the resulting `ArgumentError` and handling it defensively (e.g. logging and erroring out or falling back to safe defaults).
