## 2025-06-09 - O(1) Membership Check in Token Calculator
**Learning:** For repeated membership checks inside an enumeration (like `Enum.count(list, &Enum.member?(other_list, &1))`), converting `other_list` to a `MapSet` changes the complexity from O(N*M) to O(N + M). In Elixir, list membership is O(M), whereas `MapSet` membership is O(1).
**Action:** When performing `Enum.member?` operations within loops, especially over large lists, always explicitly convert the list to a `MapSet` beforehand to significantly reduce runtime.
