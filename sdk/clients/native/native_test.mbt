///|
test "native shim queues loci dropbox item with mulsp/muyata packets" {
  let shim = NativeLspShim::boot_proxy("ratio/lsp")
  let json = "{\"jsonrpc\":\"2.0\",\"id\":\"r-1\",\"method\":\"initialize\",\"params\":{}}"
  match shim.enqueue_emit("loci/lsp/frame_read", "frame_read", "r-1", json) {
    None => fail("expected frame_read to be in lsp dual spec")
    Some(item) => {
      assert_eq(item.loci_id, "loci/lsp/frame_read")
      assert_eq(item.function_name, "frame_read")
      assert_eq(item.request_id, "r-1")
      assert_true(item.status == Awaiting)
      assert_eq(item.mulsp_packet.handler, "lang")
      assert_eq(item.muyata_packet.handler, "lang")
      assert_true(item.mulsp_packet.capability_refs.length() >= 1)
    }
  }
  assert_eq(shim.pending_count(), 1)
  assert_eq(shim.resolved_count(), 0)
}

///|
test "native shim drains outbox for single-binary transport loop" {
  let shim = NativeLspShim::boot_proxy("ratio/lsp")
  let _ = shim.enqueue_emit(
    "loci/lsp/parse_message",
    "parse_message",
    "r-2",
    "{\"jsonrpc\":\"2.0\",\"id\":\"r-2\",\"method\":\"initialize\",\"params\":{}}",
  )
  let out = shim.drain_outbox()
  assert_eq(out.length(), 1)
  let out2 = shim.drain_outbox()
  assert_eq(out2.length(), 0)
}

///|
test "native shim resolves deferred response by request id" {
  let shim = NativeLspShim::boot_proxy("ratio/lsp")
  let _ = shim.enqueue_emit(
    "loci/lsp/parse_frame",
    "parse_frame",
    "r-3",
    "{\"jsonrpc\":\"2.0\",\"id\":\"r-3\",\"method\":\"initialize\",\"params\":{}}",
  )
  let response_wire = shim.client.encode("{\"jsonrpc\":\"2.0\",\"id\":\"r-3\",\"result\":null}")
  let resolved = shim.ingest_response_bytes(response_wire)
  assert_eq(resolved.length(), 1)
  match shim.await_response("r-3") {
    None => fail("expected resolved response for r-3")
    Some(msg) => {
      assert_true(msg.kind == @lsp.Response)
      assert_true(msg.id == Some("\"r-3\"") || msg.id == Some("r-3"))
    }
  }
  assert_eq(shim.pending_count(), 0)
  assert_eq(shim.resolved_count(), 1)
}

///|
test "native shim exposes per-loci dropbox view" {
  let shim = NativeLspShim::boot_proxy("ratio/lsp")
  let _ = shim.enqueue_emit(
    "loci/lsp/frame_read",
    "frame_read",
    "r-4",
    "{\"jsonrpc\":\"2.0\",\"id\":\"r-4\",\"method\":\"initialize\",\"params\":{}}",
  )
  let _ = shim.enqueue_emit(
    "loci/lsp/scan_bytes",
    "scan_bytes",
    "r-5",
    "{\"jsonrpc\":\"2.0\",\"id\":\"r-5\",\"method\":\"initialized\",\"params\":{}}",
  )
  let items = shim.dropbox_for_loci("loci/lsp/frame_read")
  assert_eq(items.length(), 1)
  assert_eq(items[0].request_id, "r-4")
}
