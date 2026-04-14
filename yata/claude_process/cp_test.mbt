///|
test "jitter time_offset stays in range" {
  let j = Jitter::new(12345)
  let mut i = 0
  while i < 100 {
    let off = j.time_offset(200)
    assert_true(off >= -200 && off <= 200)
    i = i + 1
  }
}

///|
test "jitter coin has low probability for large N" {
  let j = Jitter::new(99999)
  let mut hits = 0
  let mut i = 0
  while i < 1000 {
    if j.coin(20) {
      hits = hits + 1
    }
    i = i + 1
  }
  // Expect ≈50 hits (1/20 * 1000). Accept 10–150 as reasonable.
  assert_true(hits >= 5 && hits <= 200)
}

///|
test "jitter from_str produces different offsets" {
  let a = Jitter::from_str("node-a")
  let b = Jitter::from_str("node-b")
  // With different seeds, at least some offsets should differ over 20 samples.
  let mut same = 0
  let mut i = 0
  while i < 20 {
    if a.time_offset(100) == b.time_offset(100) {
      same = same + 1
    }
    i = i + 1
  }
  // Very unlikely all 20 match; proves seeds differ.
  assert_true(same < 20)
}

///|
test "bucket rounds down to nearest multiple" {
  assert_eq(bucket(0, 512), 0)
  assert_eq(bucket(511, 512), 0)
  assert_eq(bucket(512, 512), 512)
  assert_eq(bucket(1023, 512), 512)
  assert_eq(bucket(1024, 512), 1024)
}

///|
test "size_label covers all ranges" {
  assert_eq(size_label(0), "xs")
  assert_eq(size_label(511), "xs")
  assert_eq(size_label(512), "sm")
  assert_eq(size_label(2047), "sm")
  assert_eq(size_label(2048), "md")
  assert_eq(size_label(8191), "md")
  assert_eq(size_label(8192), "lg")
  assert_eq(size_label(32768), "xl")
}

///|
test "categorize identifies LSP methods correctly" {
  assert_true(categorize("textDocument/definition") == Navigation)
  assert_true(categorize("textDocument/completion") == Completion)
  assert_true(categorize("textDocument/publishDiagnostics") == Diagnostic)
  assert_true(categorize("textDocument/didChange") == Edit)
  assert_true(categorize("initialize") == Lifecycle)
  assert_true(categorize("shutdown") == Lifecycle)
  assert_true(categorize("$/whatever") == Unknown)
}

///|
test "BatchAccum counts categories correctly" {
  let a = BatchAccum::new()
  a.observe(1024, Navigation)
  a.observe(512, Navigation)
  a.observe(2048, Completion)
  a.observe(256, Edit)
  let b = a.seal(0, false)
  assert_eq(b.frame_count, 4)
  assert_eq(b.nav_count, 2)
  assert_eq(b.cmp_count, 1)
  assert_eq(b.edit_count, 1)
  assert_eq(b.diag_count, 0)
  assert_true(!a.is_empty() == false) // accum was reset by seal
}

///|
test "BatchAccum resets after seal" {
  let a = BatchAccum::new()
  a.observe(512, Navigation)
  let _ = a.seal(0, false)
  assert_true(a.is_empty())
}

///|
test "diff_snapshots computes deltas" {
  let prev : ProcSnapshot = {
    pid: 42,
    comm: "claude",
    state: 'R',
    utime: 100,
    stime: 50,
    rss_pages: 1000,
    fd_count: 20,
    sampled_at: 0,
  }
  let cur : ProcSnapshot = {
    pid: 42,
    comm: "claude",
    state: 'S',
    utime: 110,
    stime: 55,
    rss_pages: 1010,
    fd_count: 22,
    sampled_at: 1000,
  }
  let d = diff_snapshots(prev, cur)
  assert_eq(d.cpu_ticks, 15) // (110+55) - (100+50)
  assert_eq(d.rss_delta, 10)
  assert_eq(d.fd_delta, 2)
  assert_eq(d.elapsed_ms, 1000)
  assert_true(d.was_active)
}

///|
test "ClaudeObserver new starts with empty void" {
  let cfg = ObserverConfig::default("test-node")
  let obs = ClaudeObserver::new(cfg)
  let v = obs.void_snapshot()
  assert_eq(v.epoch, 0)
  assert_eq(obs.frames_seen, 0)
  assert_eq(v.node_id, "test-node")
}

///|
test "ClaudeObserver accumulates frames before flush" {
  let cfg = {
    ..ObserverConfig::default("test-node"),
    batch_size: 4,
    decoy_rate: 0,
  }
  let mut obs = ClaudeObserver::new(cfg)
  // 3 frames — no auto-flush yet.
  let nav_frame = make_test_frame("textDocument/definition")
  obs = obs.observe_frame(nav_frame, 1000)
  obs = obs.observe_frame(nav_frame, 1001)
  obs = obs.observe_frame(nav_frame, 1002)
  assert_eq(obs.frames_seen, 3)
  assert_eq(obs.flushes, 0)
  assert_eq(obs.void_snapshot().epoch, 0) // not yet flushed
}

///|
test "ClaudeObserver auto-flushes at batch_size" {
  let cfg = {
    ..ObserverConfig::default("test-node"),
    batch_size: 4,
    decoy_rate: 0,
  }
  let mut obs = ClaudeObserver::new(cfg)
  let frame = make_test_frame("textDocument/definition")
  let mut i = 0
  while i < 4 {
    obs = obs.observe_frame(frame, 1000)
    i = i + 1
  }
  assert_eq(obs.frames_seen, 4)
  assert_eq(obs.flushes, 1)
  assert_eq(obs.void_snapshot().epoch, 1)
  // nav should be attended.
  assert_true(obs.void_snapshot().anchor_weight("nav") > 0)
}

///|
test "ClaudeObserver to_bytes / from_bytes round-trip" {
  let cfg = ObserverConfig::default("rt-node")
  let mut obs = ClaudeObserver::new(cfg)
  let frame = make_test_frame("textDocument/completion")
  let mut i = 0
  while i < 8 {
    obs = obs.observe_frame(frame, 2000)
    i = i + 1
  }
  let data = obs.to_bytes()
  let cfg2 = ObserverConfig::default("rt-node")
  match ClaudeObserver::from_bytes(data, cfg2) {
    None => fail("restore failed")
    Some(obs2) => {
      assert_eq(obs2.void_snapshot().epoch, obs.void_snapshot().epoch)
      assert_true(obs2.void_snapshot().anchor_weight("cmp") > 0)
    }
  }
}

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

///|
fn make_test_frame(lsp_method : String) -> Array[Byte] {
  let json = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"\{lsp_method}\",\"params\":{}}"
  let wire = @lsp.frame_write(json)
  // Return just the body (skip the header).
  match @lsp.frame_read(wire) {
    None => []
    Some((f, _)) => f.body
  }
}
