## 2024-05-24 - O(1) Membership Lookups with MapSet
**Learning:** Changing O(N) list search to an O(1) lookup using a `MapSet` can provide immense performance gains in algorithms with nested iterative loops, effectively turning an O(N*M) calculation into an O(N+M) complexity path.
**Action:** When calculating word preservation, intersections, or looping to perform multiple `Enum.member?` checks inside an outer `Enum.count`, preemptively wrap the inner lookup list in a `MapSet`.
