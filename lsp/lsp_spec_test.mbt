///|
test "lsp dual spec includes all public functions" {
  assert_eq(@lsp.lsp_dual_spec().length(), 23)
}

///|
test "lsp dual spec category counts" {
  assert_eq(@lsp.lsp_spec_by_category(@lsp.Framing).length(), 5)
  assert_eq(@lsp.lsp_spec_by_category(@lsp.Message).length(), 2)
  assert_eq(@lsp.lsp_spec_by_category(@lsp.ClientOps).length(), 4)
  assert_eq(@lsp.lsp_spec_by_category(@lsp.ClientRuntime).length(), 8)
  assert_eq(@lsp.lsp_spec_by_category(@lsp.Scanner).length(), 4)
}

///|
test "all dual specs have positive seeds and protocols" {
  for entry in @lsp.lsp_dual_spec() {
    assert_true(entry.mulsp_seed > 0)
    assert_true(entry.muyata_seed > 0)
    assert_true(entry.mulsp_protocol.length() > 0)
    assert_true(entry.muyata_protocol.length() > 0)
  }
}

///|
test "all inverse references resolve" {
  for entry in @lsp.lsp_dual_spec() {
    assert_true(@lsp.lsp_spec_lookup(entry.inverse_name) is Some(_))
  }
}

///|
test "wrap_mulsp emits mulsp block" {
  match @lsp.wrap_mulsp("frame_write") {
    None => fail("missing frame_write wrapper")
    Some(block) => {
      assert_true(block.role == @lsp.Mulsp)
      assert_eq(block.function_name, "frame_write")
      assert_eq(block.inverse_function, "frame_read")
      assert_eq(block.protocol, "compose.frame.push")
      assert_eq(block.seed, 5)
    }
  }
}

///|
test "wrap_muyata inverts to ingestion side" {
  match @lsp.wrap_muyata("frame_write") {
    None => fail("missing frame_write inversion")
    Some(block) => {
      assert_true(block.role == @lsp.Muyata)
      assert_eq(block.function_name, "frame_read")
      assert_eq(block.inverse_function, "frame_write")
      assert_eq(block.protocol, "ingest.frame.pull")
      assert_eq(block.seed, 5)
    }
  }
}

///|
test "inversion round-trip returns original block" {
  let base = @lsp.wrap_mulsp("LspClient::ingest").unwrap()
  let round_trip = base.invert().invert()
  assert_eq(round_trip.function_name, base.function_name)
  assert_eq(round_trip.inverse_function, base.inverse_function)
  assert_true(round_trip.role == base.role)
  assert_eq(round_trip.protocol, base.protocol)
  assert_eq(round_trip.seed, base.seed)
}

///|
test "protocol lines export contract block" {
  let block = @lsp.wrap_mulsp("scan_bytes").unwrap()
  let lines = block.to_protocol_lines()
  assert_eq(lines[0], "@pattern lsp.dual.contract")
  assert_eq(lines[1], "@function scan_bytes")
  assert_eq(lines[2], "@inverse scan_str")
  assert_eq(lines[3], "@role mulsp")
  assert_eq(lines[4], "@protocol compose.scan.bytes")
}

///|
test "unknown function wrapper lookup returns none" {
  assert_true(@lsp.wrap_mulsp("not_real") is None)
  assert_true(@lsp.wrap_muyata("not_real") is None)
}

///|
test "dual binding seals when refs and obligations are satisfied" {
  let obligations : Array[@lsp.LspProofObligation] = [
    { obligation_id: "obl-dual-invert", required: true, status: @lsp.Proved },
    { obligation_id: "obl-gallery-emit", required: true, status: @lsp.Covered },
  ]
  let emission : @lsp.LspEmissionSurface = {
    docs_ref: Some("lsp/docs/lsp-dual-contract.md"),
    gallery_ref: Some("lsp/gallery/lsp-dual-contract.json"),
    wasm_plugin_ref: Some("plugin/lsp-dual.wasm"),
    deploy_queue_ref: Some("queue/lsp-dual/deploy-001"),
    composability: @lsp.FullyComposable,
    deploy_status: @lsp.Queued,
  }
  let binding = @lsp.bind_dual_contract(
    "LspClient::ingest",
    "H-lsp-dual-ingest",
    Some("lsp/tests/lsp-contracts.results.muon"),
    Some("lsp/coverage/lsp-contracts.coverage.muon"),
    Some("lsp/proofs/lsp-contracts.proof-obligations.muon"),
    Some("lsp/dialogue/lsp-codex.muonlog#seq:1"),
    obligations,
    emission,
  ).unwrap()
  assert_true(binding.can_seal())
  assert_true(binding.is_deploy_queue_ready())
  assert_true(binding.is_cross_repo_ready())
}

///|
test "dual binding blocks seal on open required obligation" {
  let obligations : Array[@lsp.LspProofObligation] = [
    { obligation_id: "obl-dual-invert", required: true, status: @lsp.Open },
  ]
  let emission : @lsp.LspEmissionSurface = {
    docs_ref: Some("lsp/docs/lsp-dual-contract.md"),
    gallery_ref: Some("lsp/gallery/lsp-dual-contract.json"),
    wasm_plugin_ref: Some("plugin/lsp-dual.wasm"),
    deploy_queue_ref: Some("queue/lsp-dual/deploy-001"),
    composability: @lsp.FullyComposable,
    deploy_status: @lsp.Deployable,
  }
  let binding = @lsp.bind_dual_contract(
    "frame_read",
    "H-lsp-dual-frame-read",
    Some("lsp/tests/lsp-contracts.results.muon"),
    Some("lsp/coverage/lsp-contracts.coverage.muon"),
    Some("lsp/proofs/lsp-contracts.proof-obligations.muon"),
    Some("lsp/dialogue/lsp-codex.muonlog#seq:2"),
    obligations,
    emission,
  ).unwrap()
  assert_true(!binding.can_seal())
  assert_true(!binding.is_deploy_queue_ready())
  assert_true(!binding.is_cross_repo_ready())
}

///|
test "dual binding emits muon-like lines for docs gallery and deploy refs" {
  let obligations : Array[@lsp.LspProofObligation] = [
    { obligation_id: "obl-dual-invert", required: true, status: @lsp.Reviewed },
  ]
  let emission : @lsp.LspEmissionSurface = {
    docs_ref: Some("lsp/docs/lsp-dual-contract.md"),
    gallery_ref: Some("lsp/gallery/lsp-dual-contract.json"),
    wasm_plugin_ref: Some("plugin/lsp-dual.wasm"),
    deploy_queue_ref: Some("queue/lsp-dual/deploy-001"),
    composability: @lsp.FullyComposable,
    deploy_status: @lsp.Queued,
  }
  let binding = @lsp.bind_dual_contract(
    "scan_bytes",
    "H-lsp-dual-scan",
    Some("lsp/tests/lsp-contracts.results.muon"),
    Some("lsp/coverage/lsp-contracts.coverage.muon"),
    Some("lsp/proofs/lsp-contracts.proof-obligations.muon"),
    Some("lsp/dialogue/lsp-codex.muonlog#seq:3"),
    obligations,
    emission,
  ).unwrap()
  let lines = binding.to_muon_lines()
  assert_eq(lines[0], "kind: :lsp_dual_contract_binding_spec")
  assert_true(lines[2].has_prefix("contract_id:"))
  assert_true(lines[3].has_prefix("@function"))
  assert_true(lines[4].has_prefix("@inverse"))
}
