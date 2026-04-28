///|
test "runtime coredump emits provenance-through lines and closes by default" {
  let dump = RuntimeCoreDump::new(
    "loci/lang/codex",
    "branch-a",
    "ctr-001",
    "boundary-walker-v0",
    77,
    "verify",
    "compose://chain/77",
    "muon://parent/55",
    "loci://return/77",
    "wasm://module/fst",
    "policy://MUYATA_POLICY/0.1",
    4,
    secret_zone_refs=["zone://keyslot/2", "zone://shapes/7"],
  )
  assert_true(dump.closed)
  let lines = dump.to_muon_lines()
  assert_eq(lines[0], "kind: :runtime_coredump")
  assert_true(lines.contains("@parent_chain_ref muon://parent/55"))
  assert_true(lines.contains("@loci_return_ref loci://return/77"))
  assert_true(lines.contains("@raw_secret_export false"))
}
