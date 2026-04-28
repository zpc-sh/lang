///|
test "wasm entrypoint boots codex flavor" {
  let host = @node.HostBridge::stub()
  let client = boot_codex("wasm-codex", host)
  assert_true(client.flavor() == @core.Codex)
  client.emit_lsp("{\"jsonrpc\":\"2.0\",\"method\":\"initialized\",\"params\":{}}")
  assert_eq(client.drain_output().length(), 1)
}
