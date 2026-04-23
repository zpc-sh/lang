## 2025-03-03 - O(N²) List.flatten in Enum.reduce

**Learning:** In Elixir, using `{[acc | [entry]] |> List.flatten(), state}` inside an `Enum.reduce` creates an O(N²) time complexity bottleneck. It iterates over the entire `acc` list on every reduction step, which destroys performance and creates huge garbage collection pressure, especially for LSP semantic token encoding which can process 10,000+ tokens per file.

**Action:** Always build large lists by prepending to the head `[entry | acc]` inside the reduction, and then call `Enum.reverse(acc)` once at the end. This ensures an O(N) time complexity and minimal GC pressure. When doing this for a flat list, prepend elements individually in reverse order.