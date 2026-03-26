## 2025-06-12 - [O(N^2) List Flattening in encode_semantic_tokens]
**Learning:** [Calling List.flatten/1 repeatedly inside Enum.reduce accumulator `[acc | [entry]] |> List.flatten()` turns linear operation into O(N^2) complexity list traversal which is extremely slow on large source files with many tokens.]
**Action:** [Use `[entry | acc]` inside Enum.reduce and then apply `data |> Enum.reverse() |> List.flatten()` outside the reduce loop once at the end.]
