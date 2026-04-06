## 2024-03-24 - [Enum.sum(Enum.map(...)) vs Enum.reduce]
**Learning:** `Enum.sum(Enum.map(collection, & &1.field))` is an anti-pattern that causes unnecessary intermediate list allocations, which can be critical memory bottlenecks for frequently calculated token/time aggregation loops in Elixir.
**Action:** Use `Enum.reduce` to do a single-pass sum or calculate multiple field sums (like baseline + enhanced tokens) concurrently.
## 2024-05-20 - Elixir Map+Sum Optimization
**Learning:** In Elixir, sequential `Enum.sum(Enum.map(...))` calls over the same list create unnecessary intermediate lists and iterate the collection multiple times. Using `Enum.reduce` in a single pass is much more efficient for multiple aggregations.
**Action:** Always replace multiple map+sum passes on the same collection with a single `Enum.reduce` that accumulates multiple values.
## 2024-05-24 - [String.length vs byte_size carefully]
**Learning:** In Elixir, do not blindly replace `String.length/1` with `byte_size/1` everywhere. While `byte_size(str) == 0` is a great O(1) replacement for `String.length(str) == 0`, using `byte_size` for length calculations (like token estimations) is incorrect for multi-byte Unicode strings and artificially inflates counts.
**Action:** Replace `String.length(str) == 0` with `str == ""` for empty checks. Leave `String.length(str)` alone when actual length counting of graphemes is required.
