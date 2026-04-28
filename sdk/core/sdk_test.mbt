///|
test "slim client selects proxy lsp implementation" {
  let host = @node.HostBridge::stub()
  let client = SlimClient::boot("sdk-proxy", Proxy, host)
  assert_true(client.lsp_impl() == @lsp.Proxy)
}

///|
test "slim client emits framed output" {
  let host = @node.HostBridge::stub()
  let client = SlimClient::boot("sdk-core", Core, host)
  client.emit_lsp("{\"jsonrpc\":\"2.0\",\"method\":\"initialized\",\"params\":{}}")
  let out = client.drain_output()
  assert_eq(out.length(), 1)
  assert_true(out[0].length() > 0)
}
