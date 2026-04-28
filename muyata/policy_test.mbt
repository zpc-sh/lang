///|
test "muyata splits fst workload into 8-cap shards with overflow clones" {
  let fsts : Array[String] = []
  let mut i = 0
  while i < 18 {
    fsts.push("fst-" + i.to_string())
    i = i + 1
  }
  let shards = split_fst_shards(fsts)
  assert_eq(shards.length(), 3)
  assert_eq(shards[0].fsts.length(), 8)
  assert_eq(shards[1].fsts.length(), 8)
  assert_eq(shards[2].fsts.length(), 2)
  assert_true(!shards[0].is_overflow)
  assert_true(shards[1].is_overflow)
  assert_true(shards[2].is_overflow)
}

///|
test "compose chain is append-only and policy-valid" {
  let chain = ComposeChain::new("codex-terminal")
    .append_op("Compose", "tape://stdin", "tape://stdout", "tape://merged")
    .append_op("Determinize", "tape://merged", "epsilon://", "tape://det")
    .append_op("Prune", "tape://det", "threshold://0.2", "tape://pruned")
  assert_true(chain.is_append_only())
  assert_true(validate_compose_chain(chain))
  let lines = chain.to_muon_lines()
  assert_eq(lines[0], "kind: :muyata_compose_chain")
  assert_true(lines.contains("@append_only true"))
}

///|
test "fail-close coredump emits only when compose provenance is valid" {
  let chain = ComposeChain::new("codex-terminal")
    .append_op("Compose", "tape://stdin", "tape://stdout", "tape://merged")
    .append_op("Determinize", "tape://merged", "epsilon://", "tape://det")
  match emit_fail_close_coredump(
    chain,
    "loci/lang/codex",
    "branch-1",
    "ctr-001",
    "boundary-walker-v0",
    "collapsed",
    "muon://parent/9",
    "loci://return/9",
    "wasm://module/fst",
    3,
    secret_zone_refs=["zone://keys/1"],
  ) {
    Some(dump) => {
      let lines = dump.to_muon_lines()
      assert_true(lines.contains("@close_after_dump true"))
      assert_true(lines.contains("@parent_chain_ref muon://parent/9"))
      assert_true(lines.contains("@loci_return_ref loci://return/9"))
    }
    None => fail("expected coredump")
  }
}
