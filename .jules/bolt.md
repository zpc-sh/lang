## 2024-03-24 - [Enum.sum(Enum.map(...)) vs Enum.reduce]
**Learning:** `Enum.sum(Enum.map(collection, & &1.field))` is an anti-pattern that causes unnecessary intermediate list allocations, which can be critical memory bottlenecks for frequently calculated token/time aggregation loops in Elixir.
**Action:** Use `Enum.reduce` to do a single-pass sum or calculate multiple field sums (like baseline + enhanced tokens) concurrently.
