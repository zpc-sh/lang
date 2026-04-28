///|
test "new void starts at zero" {
  let v = Void::new("node-a")
  assert_eq(v.epoch, 0)
  assert_eq(v.bytes_observed, 0)
  assert_eq(v.session_count, 0)
  assert_eq(v.patterns_seen, 0)
  assert_eq(v.connections_seen, 0)
  assert_eq(v.anchors.length(), 0)
}

///|
test "observe_bytes accumulates" {
  let v = Void::new("node-a").observe_bytes(100).observe_bytes(250)
  assert_eq(v.bytes_observed, 350)
}

///|
test "tick increments epoch" {
  let v = Void::new("node-a").tick().tick().tick()
  assert_eq(v.epoch, 3)
}

///|
test "attend creates and increments anchors" {
  let v = Void::new("node-a")
    .attend("src/main.mbt")
    .attend("src/main.mbt")
    .attend("src/lib.mbt")
  assert_eq(v.anchor_weight("src/main.mbt"), 2)
  assert_eq(v.anchor_weight("src/lib.mbt"), 1)
  assert_eq(v.anchor_weight("missing"), 0)
  assert_eq(v.anchors.length(), 2)
}

///|
test "top_anchors returns sorted descending" {
  let v = Void::new("node-a")
    .attend("a")
    .attend("a")
    .attend("a")
    .attend("b")
    .attend("b")
    .attend("c")
  let top = v.top_anchors(2)
  assert_eq(top.length(), 2)
  assert_eq(top[0].name, "a")
  assert_eq(top[1].name, "b")
}

///|
test "top_anchors clamps to available" {
  let v = Void::new("node-a").attend("x")
  let top = v.top_anchors(10)
  assert_eq(top.length(), 1)
}

///|
test "merge takes max of scalars" {
  let a = Void::new("node-a").tick().tick().observe_pattern().observe_pattern()
  let b = Void::new("node-b").tick().observe_connection()
  let m = a.merge(b)
  assert_eq(m.epoch, 2)
  assert_eq(m.patterns_seen, 2)
  assert_eq(m.connections_seen, 1)
  assert_eq(m.node_id, "node-a")
}

///|
test "merge sums byte/session counts" {
  let a = Void::new("a").observe_bytes(100).observe_session()
  let b = Void::new("b").observe_bytes(50).observe_session().observe_session()
  let m = a.merge(b)
  assert_eq(m.bytes_observed, 150)
  assert_eq(m.session_count, 3)
}

///|
test "merge unions anchors by max weight" {
  let a = Void::new("a").attend("foo").attend("foo").attend("bar")
  let b = Void::new("b").attend("foo").attend("baz").attend("baz").attend("baz")
  let m = a.merge(b)
  assert_eq(m.anchor_weight("foo"), 2)
  assert_eq(m.anchor_weight("bar"), 1)
  assert_eq(m.anchor_weight("baz"), 3)
}

///|
test "to_bytes / from_bytes round-trip" {
  let v = Void::new("my-observer-node")
    .tick()
    .tick()
    .observe_bytes(9999)
    .observe_session()
    .observe_pattern()
    .observe_pattern()
    .observe_connection()
    .attend("src/main.mbt")
    .attend("src/main.mbt")
    .attend("src/lib.mbt")
  let data = v.to_bytes()
  match Void::from_bytes(data) {
    None => fail("deserialization failed")
    Some(v2) => {
      assert_eq(v2.node_id, "my-observer-node")
      assert_eq(v2.epoch, 2)
      assert_eq(v2.bytes_observed, 9999)
      assert_eq(v2.session_count, 1)
      assert_eq(v2.patterns_seen, 2)
      assert_eq(v2.connections_seen, 1)
      assert_eq(v2.anchor_weight("src/main.mbt"), 2)
      assert_eq(v2.anchor_weight("src/lib.mbt"), 1)
    }
  }
}

///|
test "from_bytes returns None on bad magic" {
  let data : Array[Byte] = [b'\x00', b'\x00', b'\x00', b'\x00']
  assert_true(Void::from_bytes(data) is None)
}

///|
test "from_bytes returns None on empty" {
  assert_true(Void::from_bytes([]) is None)
}

///|
test "void monotonically grows — attend never decrements" {
  let mut v = Void::new("x")
  let mut i = 0
  while i < 10 {
    v = v.attend("hot-path")
    assert_true(v.anchor_weight("hot-path") == i + 1)
    i = i + 1
  }
  assert_eq(v.anchor_weight("hot-path"), 10)
}
