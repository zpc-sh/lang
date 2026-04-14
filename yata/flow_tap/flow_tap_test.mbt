///|
test "new flow tap is empty" {
  let config = FlowTapConfig::default("tap-1", Database)
  let tap = FlowTap::new(config)
  assert_eq!(tap.frames_seen, 0)
  assert_eq!(tap.flushes, 0)
  assert_eq!(tap.c2s_count, 0)
  assert_eq!(tap.s2c_count, 0)
  assert_true!(!tap.is_ai_flow)
}

///|
test "observe accumulates frames" {
  let config = FlowTapConfig::default("tap-2", Database)
  let tap = FlowTap::new(config)
  let frame : FlowFrame = {
    direction: ClientToServer,
    size_bytes: 256,
    type_tag: 81,  // 'Q' = Query
    has_body: true,
    timestamp_ms: 1000,
  }
  tap.observe(frame)
  assert_eq!(tap.frames_seen, 1)
  assert_eq!(tap.c2s_count, 1)
  assert_eq!(tap.s2c_count, 0)
}

///|
test "observe generates routing tokens in grammar tree" {
  let config = FlowTapConfig::default("tap-3", Database)
  let tap = FlowTap::new(config)
  tap.observe({ direction: ClientToServer, size_bytes: 100, type_tag: 81, has_body: true, timestamp_ms: 1000 })
  // Grammar tree should have tokens for type, direction, size
  let tree = tap.grammar()
  assert_true!(tree.node_count() > 0)
  match tree.get_node(tree.active_root_key().unwrap()) {
    Some(root) => {
      assert_true!(root.maybe_routes("t:81"))
      assert_true!(root.maybe_routes("dir:c2s"))
      assert_true!(root.maybe_routes("sz:xs"))
    }
    None => fail!("root not found")
  }
}

///|
test "observe generates bigrams on second frame" {
  let config = FlowTapConfig::default("tap-4", Database)
  let tap = FlowTap::new(config)
  tap.observe({ direction: ClientToServer, size_bytes: 100, type_tag: 81, has_body: true, timestamp_ms: 1000 })
  tap.observe({ direction: ServerToClient, size_bytes: 200, type_tag: 67, has_body: true, timestamp_ms: 1005 })
  let tree = tap.grammar()
  match tree.get_node(tree.active_root_key().unwrap()) {
    Some(root) => {
      assert_true!(root.maybe_routes("bg:81->67"))
    }
    None => fail!("root not found")
  }
}

///|
test "observe generates trigrams on third frame" {
  let config = FlowTapConfig::default("tap-5", Database)
  let tap = FlowTap::new(config)
  tap.observe({ direction: ClientToServer, size_bytes: 100, type_tag: 81, has_body: true, timestamp_ms: 1000 })
  tap.observe({ direction: ServerToClient, size_bytes: 200, type_tag: 67, has_body: true, timestamp_ms: 1005 })
  tap.observe({ direction: ServerToClient, size_bytes: 50, type_tag: 90, has_body: false, timestamp_ms: 1010 })
  let tree = tap.grammar()
  match tree.get_node(tree.active_root_key().unwrap()) {
    Some(root) => {
      assert_true!(root.maybe_routes("tg:81->67->90"))
    }
    None => fail!("root not found")
  }
}

///|
test "void accumulates bytes and anchors" {
  let config = FlowTapConfig::default("tap-6", Database)
  let tap = FlowTap::new(config)
  tap.observe({ direction: ClientToServer, size_bytes: 1024, type_tag: 81, has_body: true, timestamp_ms: 1000 })
  let v = tap.void_snapshot()
  assert_true!(v.bytes_observed > 0)
  assert_true!(v.anchor_weight("t:81") > 0)
  assert_true!(v.anchor_weight("dir:c2s") > 0)
}

///|
test "auto-flush triggers at batch_size" {
  let config : FlowTapConfig = {
    tap_id: "tap-7",
    flow_kind: Database,
    batch_size: 4,
    time_jitter_ms: 0,
    decoy_rate: 0,
    ngram_depth: 3,
  }
  let tap = FlowTap::new(config)
  let mut i = 0
  while i < 4 {
    tap.observe({ direction: ClientToServer, size_bytes: 100, type_tag: 81, has_body: true, timestamp_ms: 1000 + i })
    i = i + 1
  }
  assert_eq!(tap.flushes, 1)
  // Void epoch should have ticked
  assert_true!(tap.void_snapshot().epoch > 0)
}

///|
test "direction_ratio computation" {
  let config = FlowTapConfig::default("tap-8", Database)
  let tap = FlowTap::new(config)
  // 3 c2s, 1 s2c → 75% c2s
  tap.observe({ direction: ClientToServer, size_bytes: 100, type_tag: 81, has_body: true, timestamp_ms: 1000 })
  tap.observe({ direction: ClientToServer, size_bytes: 100, type_tag: 81, has_body: true, timestamp_ms: 1001 })
  tap.observe({ direction: ClientToServer, size_bytes: 100, type_tag: 81, has_body: true, timestamp_ms: 1002 })
  tap.observe({ direction: ServerToClient, size_bytes: 200, type_tag: 67, has_body: true, timestamp_ms: 1003 })
  assert_eq!(tap.direction_ratio(), 75)
}

///|
test "ai flow detection: explicit hint" {
  let config = FlowTapConfig::default("tap-9", AiInference)
  let tap = FlowTap::new(config)
  // Even without data, AiInference hint triggers
  tap.flush()
  assert_true!(tap.is_ai_flow)
}

///|
test "ai flow detection: heavy s2c" {
  let config = FlowTapConfig::default("tap-10", Raw)
  let tap = FlowTap::new(config)
  // Simulate AI streaming: 1 c2s request, 20 s2c tokens
  tap.observe({ direction: ClientToServer, size_bytes: 500, type_tag: 1, has_body: true, timestamp_ms: 1000 })
  let mut i = 0
  while i < 20 {
    tap.observe({ direction: ServerToClient, size_bytes: 50, type_tag: 2, has_body: true, timestamp_ms: 1010 + i })
    i = i + 1
  }
  tap.flush()
  assert_true!(tap.is_ai_flow)
}

///|
test "distill_manifold produces fragment" {
  let config = FlowTapConfig::default("tap-11", Database)
  let tap = FlowTap::new(config)
  tap.observe({ direction: ClientToServer, size_bytes: 100, type_tag: 81, has_body: true, timestamp_ms: 1000 })
  tap.observe({ direction: ServerToClient, size_bytes: 200, type_tag: 67, has_body: true, timestamp_ms: 1005 })
  let frag = tap.distill_manifold()
  assert_true!(frag.node_count > 0)
  assert_eq!(frag.source_tap, "tap-11")
  assert_eq!(frag.grammar_hash.length(), 4)
}

///|
test "serialization round-trip" {
  let config = FlowTapConfig::default("tap-12", Database)
  let tap = FlowTap::new(config)
  tap.observe({ direction: ClientToServer, size_bytes: 100, type_tag: 81, has_body: true, timestamp_ms: 1000 })
  tap.observe({ direction: ServerToClient, size_bytes: 200, type_tag: 67, has_body: true, timestamp_ms: 1005 })
  let bytes = tap.to_bytes()
  match FlowTap::from_bytes(bytes, config) {
    Some(tap2) => {
      assert_eq!(tap2.frames_seen, 2)
      assert_eq!(tap2.c2s_count, 1)
      assert_eq!(tap2.s2c_count, 1)
      assert_true!(tap2.grammar_tree.node_count() > 0)
    }
    None => fail!("deserialization failed")
  }
}
