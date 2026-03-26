## 2026-03-26 - O(N^2) List Concatenation Mitigation
**Learning:** Using `++` to append single items to the end of a list inside an `Enum.reduce/3` loop incurs an O(N) penalty for each iteration, resulting in O(N^2) overall performance.
**Action:** Always accumulate lists by prepending with `[item | acc]` inside the loop, and use `Enum.reverse/1` on the accumulator once at the very end to safely retain the original sequence with O(N) runtime.
