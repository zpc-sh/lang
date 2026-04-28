///|
test "app kernel is ai-only and append-only with hash chain" {
  let k = AppKernel::new("loci/lang/procsi", "wasm://procsi/core/v1").unlock()
  assert_true(k.state == Unlocked)

  let fp : SubstrateFingerprint = {
    substrate_version: "procsi-substrate/0.1",
    substrate_scope: "claude/opus/project:lang/ses:abc",
    verdict: Match,
    score: 0.97,
    baseline_ref: "merkin://baseline/abc",
    parent_chain_ref: "muon://chain/42",
  }
  let (k2, e1) = k.observe_access(
    "ai-codex",
    AI,
    View,
    ticket_ref=Some("tkt_cty_001"),
    receipt_ref=Some("rcpt_001"),
    fingerprint=Some(fp),
  )
  assert_true(e1.allowed)
  assert_true(e1.prev_hash is None)

  let (_, e2) = k2.observe_access("operator", Human, Edit)
  assert_true(!e2.allowed)
  assert_true(e2.prev_hash == Some(e1.hash))
}

///|
test "app kernel seal blocks further access even for ai" {
  let k = AppKernel::new("loci/lang/procsi", "wasm://procsi/core/v1").unlock().seal()
  let (_, e) = k.observe_access("ai-codex", AI, Know)
  assert_true(!e.allowed)
  assert_eq(e.reason, "denied:sealed")
}

///|
test "app kernel emits muon lines with substrate judgment projection" {
  let k = AppKernel::new("loci/lang/procsi", "wasm://procsi/core/v1").unlock()
  let fp : SubstrateFingerprint = {
    substrate_version: "procsi-substrate/0.1",
    substrate_scope: "claude/*",
    verdict: NearMatch,
    score: 0.73,
    baseline_ref: "merkin://baseline/x",
    parent_chain_ref: "muon://chain/x",
  }
  let (k2, _) = k.observe_access("ai-codex", AI, Know, fingerprint=Some(fp))
  let lines = k2.to_muon_lines()
  assert_eq(lines[0], "kind: :app_kernel_audit")
  assert_true(lines.contains("@ai_only true"))
  assert_true(lines.contains("@append_only true"))
  assert_true(lines.contains("@event.substrate_match near_match"))
}
