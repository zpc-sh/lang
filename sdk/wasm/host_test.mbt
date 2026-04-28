///|
fn host_put_slot1(s : String) -> Unit {
  let mut i = 0
  for ch in s {
    lm_sdk_put(i, ch.to_int())
    i = i + 1
  }
  lm_sdk_len(i)
}

///|
fn host_put_slot2(s : String) -> Unit {
  let mut i = 0
  for ch in s {
    lm_sdk_put2(i, ch.to_int())
    i = i + 1
  }
  lm_sdk_len2(i)
}

///|
fn host_out_bytes() -> Array[Byte] {
  let n = lm_sdk_out_len()
  let out = Array::make(n, b'\x00')
  let mut i = 0
  while i < n {
    out[i] = lm_sdk_out_get(i).to_byte()
    i = i + 1
  }
  out
}

///|
fn host_out_str() -> String {
  let bytes = host_out_bytes()
  let sb = StringBuilder::new()
  for b in bytes {
    let cp = b.to_int()
    if cp >= 0x20 && cp <= 0x7E {
      sb.write_char(cp.to_char().unwrap())
    }
  }
  sb.to_string()
}

///|
fn host_join_lines(lines : Array[String]) -> String {
  let sb = StringBuilder::new()
  let mut i = 0
  let n = lines.length()
  while i < n {
    if i > 0 {
      sb.write_char('\n')
    }
    sb.write_string(lines[i])
    i = i + 1
  }
  sb.to_string()
}

///|
test "lm_sdk boot emit and drain" {
  lm_sdk_profile_set(3)
  host_put_slot1("sdk-host")
  assert_eq(lm_sdk_boot(), 1)
  assert_eq(lm_sdk_ready(), 1)
  assert_eq(lm_sdk_flavor(), 3)

  host_put_slot1("{\"jsonrpc\":\"2.0\",\"method\":\"initialized\",\"params\":{}}")
  assert_eq(lm_sdk_emit(), 1)
  assert_eq(lm_sdk_drain(), 1)
  assert_true(lm_sdk_out_len() > 0)
}

///|
test "lm_sdk executes deploy-ready dual contract via executeCommand channel" {
  lm_sdk_profile_set(3)
  host_put_slot1("contract-host")
  assert_eq(lm_sdk_boot(), 1)

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
  let payload = host_join_lines(binding.to_muon_lines())
  host_put_slot1(payload)
  host_put_slot2("workspace.executeCommand,codex.connector.channel")

  assert_eq(lm_sdk_emit_contract(), 1)
  assert_eq(lm_sdk_drain(), 1)
  let frame = host_out_str()
  assert_true(frame.contains("workspace/executeCommand"))
  assert_true(frame.contains("lsp.dual.contract.execute"))
}

///|
test "lm_sdk executes loci codex-codex handshake artifact via executeCommand channel" {
  lm_sdk_profile_set(3)
  host_put_slot1("contract-handshake-host")
  assert_eq(lm_sdk_boot(), 1)

  let lines = @codex.codex_codex_handshake_artifact(
    "H-codex-codex-001",
    "loci/codex/dialogue/chatgpt-codex.muonlog#seq:1",
    "queue/lsp-dual/deploy-001",
  )
  host_put_slot1(host_join_lines(lines))
  host_put_slot2("codex.connector.channel")

  assert_eq(lm_sdk_emit_contract(), 1)
  assert_eq(lm_sdk_drain(), 1)
  let frame = host_out_str()
  assert_true(frame.contains("workspace/executeCommand"))
  assert_true(frame.contains("lsp.dual.contract.execute"))
}

///|
test "lm_sdk contract emit blocks when contract is not deploy-ready" {
  lm_sdk_profile_set(3)
  host_put_slot1("contract-not-ready-host")
  assert_eq(lm_sdk_boot(), 1)

  let obligations : Array[@lsp.LspProofObligation] = [
    { obligation_id: "obl-dual-invert", required: true, status: @lsp.Open },
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
    "frame_read",
    "H-lsp-dual-not-ready",
    Some("lsp/tests/lsp-contracts.results.muon"),
    Some("lsp/coverage/lsp-contracts.coverage.muon"),
    Some("lsp/proofs/lsp-contracts.proof-obligations.muon"),
    Some("lsp/dialogue/lsp-codex.muonlog#seq:2"),
    obligations,
    emission,
  ).unwrap()
  host_put_slot1(host_join_lines(binding.to_muon_lines()))
  host_put_slot2("codex.connector.channel")

  assert_eq(lm_sdk_emit_contract(), 0)
}

///|
test "lm_sdk contract emit blocks when codex connector channel cap is missing" {
  lm_sdk_profile_set(3)
  host_put_slot1("contract-no-channel-host")
  assert_eq(lm_sdk_boot(), 1)

  let obligations : Array[@lsp.LspProofObligation] = [
    { obligation_id: "obl-dual-invert", required: true, status: @lsp.Proved },
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
    "H-lsp-dual-no-channel",
    Some("lsp/tests/lsp-contracts.results.muon"),
    Some("lsp/coverage/lsp-contracts.coverage.muon"),
    Some("lsp/proofs/lsp-contracts.proof-obligations.muon"),
    Some("lsp/dialogue/lsp-codex.muonlog#seq:4"),
    obligations,
    emission,
  ).unwrap()
  host_put_slot1(host_join_lines(binding.to_muon_lines()))
  host_put_slot2("workspace.executeCommand,build.emit")

  assert_eq(lm_sdk_emit_contract(), 0)
}

///|
test "lm_sdk contract preflight reports gate status bits" {
  lm_sdk_profile_set(3)
  host_put_slot1("contract-preflight-host")
  assert_eq(lm_sdk_boot(), 1)

  let obligations : Array[@lsp.LspProofObligation] = [
    { obligation_id: "obl-dual-invert", required: true, status: @lsp.Proved },
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
    "H-lsp-dual-preflight",
    Some("lsp/tests/lsp-contracts.results.muon"),
    Some("lsp/coverage/lsp-contracts.coverage.muon"),
    Some("lsp/proofs/lsp-contracts.proof-obligations.muon"),
    Some("lsp/dialogue/lsp-codex.muonlog#seq:5"),
    obligations,
    emission,
  ).unwrap()

  host_put_slot1(host_join_lines(binding.to_muon_lines()))
  host_put_slot2("codex.connector.channel")
  assert_eq(lm_sdk_contract_preflight(), 3)

  host_put_slot2("workspace.executeCommand")
  assert_eq(lm_sdk_contract_preflight(), 1)
}

///|
test "lm_sdk codex mulsp build from function CSV" {
  host_put_slot1("codex-host")
  host_put_slot2("edit.apply,build.emit,edit.apply")
  assert_eq(lm_sdk_codex_mulsp(), 1)

  let data = host_out_bytes()
  match @mulsp.MulspState::from_bytes(data) {
    Some(state) => {
      assert_eq(state.handler, "codex")
      assert_eq(state.capability_refs.length(), 2)
      assert_eq(state.capability_refs[0], "fn:edit.apply")
      assert_eq(state.capability_refs[1], "fn:build.emit")
    }
    None => fail("expected mulsp bytes")
  }
}

///|
test "lm_sdk managed host logs and checkpoint blob roundtrip" {
  lm_sdk_host_mode_set(1)
  lm_sdk_host_caps_set(0, 1, 1, 1, 0)
  host_put_slot2("wasmex")
  lm_sdk_host_name_from_slot2()
  lm_sdk_host_now_set(42)
  lm_sdk_profile_set(0)
  host_put_slot1("managed-node")
  assert_eq(lm_sdk_boot(), 1)
  assert_true(lm_sdk_host_log_pending() > 0)
  assert_eq(lm_sdk_host_log_drain(), 1)
  assert_true(host_out_str().has_prefix("info:node: booted"))

  assert_eq(lm_sdk_checkpoint(), 1)
  let key = host_out_str()
  assert_true(key.length() > 0)
  host_put_slot1(key)
  assert_eq(lm_sdk_host_blob_has_slot1(), 1)
  assert_eq(lm_sdk_host_blob_get_slot1(), 1)
  assert_true(lm_sdk_out_len() > 0)
}
