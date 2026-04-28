///|
test "frame_write produces correct header" {
  let body = "{\"jsonrpc\":\"2.0\",\"method\":\"initialized\",\"params\":{}}"
  let wire = frame_write(body)
  let s = @lsp.bytes_to_str_pub(wire)
  let expected_header = "Content-Length: \{body.length()}\r\n\r\n"
  assert_true(s.has_prefix(expected_header))
}

///|
test "frame_read round-trips a single frame" {
  let body = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}"
  let wire = frame_write(body)
  match frame_read(wire) {
    None => fail("expected a frame")
    Some((f, rest)) => {
      assert_eq(f.content_length, body.length())
      assert_eq(rest.length(), 0)
      let got = @lsp.bytes_to_str_pub(f.body)
      assert_eq(got, body)
    }
  }
}

///|
test "frame_read returns None for incomplete frame" {
  let body = "{\"jsonrpc\":\"2.0\",\"method\":\"initialized\",\"params\":{}}"
  let wire = frame_write(body)
  // truncate to only the header portion
  let partial = @lsp.slice_pub(wire, 0, 25)
  assert_true(frame_read(partial) is None)
}

///|
test "frame_drain extracts multiple frames" {
  let b1 = "{\"jsonrpc\":\"2.0\",\"method\":\"initialized\",\"params\":{}}"
  let b2 = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}"
  let w1 = frame_write(b1)
  let w2 = frame_write(b2)
  let combined : Array[Byte] = []
  for b in w1 {
    combined.push(b)
  }
  for b in w2 {
    combined.push(b)
  }
  let (frames, rest) = frame_drain(combined)
  assert_eq(frames.length(), 2)
  assert_eq(rest.length(), 0)
}

///|
test "parse_message classifies Request" {
  let json = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}"
  let msg = parse_message(json)
  assert_true(msg.kind == Request)
  assert_true(msg.id == Some("1"))
  assert_true(msg.lsp_method == Some("initialize"))
}

///|
test "parse_message classifies Notification" {
  let json = "{\"jsonrpc\":\"2.0\",\"method\":\"initialized\",\"params\":{}}"
  let msg = parse_message(json)
  assert_true(msg.kind == Notification)
  assert_true(msg.id is None)
  assert_true(msg.lsp_method == Some("initialized"))
}

///|
test "parse_message classifies Response" {
  let json = "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":null}"
  let msg = parse_message(json)
  assert_true(msg.kind == Response)
  assert_true(msg.id == Some("1"))
  assert_true(msg.lsp_method is None)
}

///|
test "parse_frame from wire bytes" {
  let body = "{\"jsonrpc\":\"2.0\",\"method\":\"initialized\",\"params\":{}}"
  let wire = frame_write(body)
  match frame_read(wire) {
    None => fail("no frame")
    Some((f, _)) => {
      let msg = parse_frame(f)
      assert_true(msg.kind == Notification)
    }
  }
}

///|
test "lsp client proxy ingests and parses frame" {
  let client = LspClient::proxy()
  let body = "{\"jsonrpc\":\"2.0\",\"method\":\"initialized\",\"params\":{}}"
  let wire = client.encode(body)
  let frames = client.ingest(wire)
  assert_eq(frames.length(), 1)
  let msg = client.parse(frames[0])
  assert_true(msg.kind == Notification)
  assert_true(msg.lsp_method == Some("initialized"))
}

///|
test "lsp client can swap implementations via ops" {
  let client = LspClient::new(LspClientOps::claude_process())
  assert_true(client.impl_id() == ClaudeProcess)
  let body = "{\"jsonrpc\":\"2.0\",\"id\":7,\"method\":\"initialize\",\"params\":{}}"
  let wire = client.encode(body)
  let frames = client.ingest(wire)
  assert_eq(frames.length(), 1)
  let msg = client.parse(frames[0])
  assert_true(msg.kind == Request)
  assert_true(msg.id == Some("7"))
}

///|
test "lsp client keeps partial bytes buffered" {
  let client = LspClient::proxy()
  let body = "{\"jsonrpc\":\"2.0\",\"method\":\"initialized\",\"params\":{}}"
  let wire = client.encode(body)
  let partial = @lsp.slice_pub(wire, 0, wire.length() - 5)
  let tail = @lsp.slice_pub(wire, wire.length() - 5, wire.length())
  let first = client.ingest(partial)
  assert_eq(first.length(), 0)
  assert_true(client.pending_bytes() > 0)
  let second = client.ingest(tail)
  assert_eq(second.length(), 1)
  assert_eq(client.pending_bytes(), 0)
}
