## 2024-05-20 - Elixir Map+Sum Optimization
**Learning:** In Elixir, sequential `Enum.sum(Enum.map(...))` calls over the same list create unnecessary intermediate lists and iterate the collection multiple times. Using `Enum.reduce` in a single pass is much more efficient for multiple aggregations.
**Action:** Always replace multiple map+sum passes on the same collection with a single `Enum.reduce` that accumulates multiple values.
