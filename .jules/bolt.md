## 2024-03-24 - [Enum.sum(Enum.map(...)) vs Enum.reduce]
**Learning:** `Enum.sum(Enum.map(collection, & &1.field))` is an anti-pattern that causes unnecessary intermediate list allocations, which can be critical memory bottlenecks for frequently calculated token/time aggregation loops in Elixir.
**Action:** Use `Enum.reduce` to do a single-pass sum or calculate multiple field sums (like baseline + enhanced tokens) concurrently.
## 2024-05-20 - Elixir Map+Sum Optimization
**Learning:** In Elixir, sequential `Enum.sum(Enum.map(...))` calls over the same list create unnecessary intermediate lists and iterate the collection multiple times. Using `Enum.reduce` in a single pass is much more efficient for multiple aggregations.
**Action:** Always replace multiple map+sum passes on the same collection with a single `Enum.reduce` that accumulates multiple values.
