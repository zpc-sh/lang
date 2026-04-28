///|
test "preflight bitmask encodes readiness and channel gate" {
  assert_eq(@portable_wasi.preflight_bits(false, false), 0)
  assert_eq(@portable_wasi.preflight_bits(true, false), 1)
  assert_eq(@portable_wasi.preflight_bits(false, true), 2)
  assert_eq(@portable_wasi.preflight_bits(true, true), 3)
}

///|
test "contract block readiness markers must both be present" {
  let ready =
    "kind: :x\n@deploy_ready true\n@cross_repo_ready true\n@required_capability fn:codex.connector.channel"
  let not_ready = "kind: :x\n@deploy_ready true"
  assert_true(@portable_wasi.block_has_ready_markers(ready))
  assert_true(!@portable_wasi.block_has_ready_markers(not_ready))
}

///|
test "execute command envelope is emitted as workspace executeCommand" {
  let json = @portable_wasi.execute_command_json("lsp.dual.contract.execute", "line-1\nline-2")
  assert_true(json.contains("workspace/executeCommand"))
  assert_true(json.contains("lsp.dual.contract.execute"))
  assert_true(json.contains("line-1\\nline-2"))
}
