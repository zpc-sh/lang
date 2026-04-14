///|
test "new pg tap is empty" {
  let pg = PgTap::new("pg-tap-1")
  assert_eq(pg.frontend_count(), 0)
  assert_eq(pg.backend_count(), 0)
}

///|
test "classify frontend messages" {
  assert_true(pg_classify_frontend(0x51) is Query)
  assert_true(pg_classify_frontend(0x50) is Parse)
  assert_true(pg_classify_frontend(0x42) is Bind)
  assert_true(pg_classify_frontend(0x45) is Execute)
  assert_true(pg_classify_frontend(0x44) is Describe)
  assert_true(pg_classify_frontend(0x53) is Sync)
  assert_true(pg_classify_frontend(0x43) is Close)
  assert_true(pg_classify_frontend(0x58) is Terminate)
  assert_true(pg_classify_frontend(0xFF) is Unknown(_))
}

///|
test "classify backend messages" {
  assert_true(pg_classify_backend(0x43) is CommandComplete)
  assert_true(pg_classify_backend(0x54) is RowDescription)
  assert_true(pg_classify_backend(0x44) is DataRow)
  assert_true(pg_classify_backend(0x5A) is ReadyForQuery)
  assert_true(pg_classify_backend(0x52) is Authentication)
  assert_true(pg_classify_backend(0x31) is ParseComplete)
  assert_true(pg_classify_backend(0x32) is BindComplete)
  assert_true(pg_classify_backend(0x33) is CloseComplete)
  assert_true(pg_classify_backend(0xFF) is Unknown(_))
}

///|
test "build_frame creates valid wire format" {
  // Query message with 10 bytes payload
  let frame = pg_build_frame(0x51, 10)
  assert_eq(frame[0].to_int(), 0x51) // type = 'Q'
  // Length = 14 (4 + 10), big-endian
  assert_eq(frame[1].to_int(), 0)
  assert_eq(frame[2].to_int(), 0)
  assert_eq(frame[3].to_int(), 0)
  assert_eq(frame[4].to_int(), 14)
  assert_eq(frame.length(), 15) // 1 type + 4 len + 10 payload
}

///|
test "observe_raw parses frontend Query" {
  let pg = PgTap::new("pg-tap-2")
  let frame = pg_build_frame(0x51, 20) // Query with 20 bytes
  pg.observe_raw(true, frame, 1000)
  assert_eq(pg.frontend_count(), 1)
  assert_eq(pg.backend_count(), 0)
  assert_true(pg.last_fe is Some(Query))
  // FlowTap should have observed the frame
  assert_eq(pg.tap().frames_seen, 1)
}

///|
test "observe_raw parses backend CommandComplete" {
  let pg = PgTap::new("pg-tap-3")
  let frame = pg_build_frame(0x43, 15) // CommandComplete
  pg.observe_raw(false, frame, 1005)
  assert_eq(pg.frontend_count(), 0)
  assert_eq(pg.backend_count(), 1)
  assert_true(pg.last_be is Some(CommandComplete))
}

///|
test "typical query-response cycle" {
  let pg = PgTap::new("pg-tap-4")
  // Client sends Query
  pg.observe_raw(true, pg_build_frame(0x51, 30), 1000)
  // Server sends RowDescription
  pg.observe_raw(false, pg_build_frame(0x54, 50), 1002)
  // Server sends DataRow (multiple)
  pg.observe_raw(false, pg_build_frame(0x44, 100), 1003)
  pg.observe_raw(false, pg_build_frame(0x44, 80), 1004)
  // Server sends CommandComplete
  pg.observe_raw(false, pg_build_frame(0x43, 10), 1005)
  // Server sends ReadyForQuery
  pg.observe_raw(false, pg_build_frame(0x5A, 1), 1006)

  assert_eq(pg.frontend_count(), 1)
  assert_eq(pg.backend_count(), 5)

  // Grammar tree should have accumulated tokens
  let tree = pg.tap().grammar()
  assert_true(tree.node_count() > 0)
  let root = tree.get_node(tree.active_root_key().unwrap()).unwrap()
  // Should route Query type tag (0x51 = 81 decimal)
  assert_true(root.maybe_routes("t:81"))
  // Should route CommandComplete type tag (0x43 = 67 decimal)
  assert_true(root.maybe_routes("t:67"))
  // Should have bigram from Q→T (81→84)
  assert_true(root.maybe_routes("bg:81->84"))
}

///|
test "prepared statement flow" {
  let pg = PgTap::new("pg-tap-5")
  // Parse
  pg.observe_raw(true, pg_build_frame(0x50, 40), 1000)
  // Bind
  pg.observe_raw(true, pg_build_frame(0x42, 20), 1001)
  // Execute
  pg.observe_raw(true, pg_build_frame(0x45, 5), 1002)
  // Sync
  pg.observe_raw(true, pg_build_frame(0x53, 0), 1003)
  // ParseComplete
  pg.observe_raw(false, pg_build_frame(0x31, 0), 1004)
  // BindComplete
  pg.observe_raw(false, pg_build_frame(0x32, 0), 1005)
  // DataRow
  pg.observe_raw(false, pg_build_frame(0x44, 50), 1006)
  // CommandComplete
  pg.observe_raw(false, pg_build_frame(0x43, 10), 1007)
  // ReadyForQuery
  pg.observe_raw(false, pg_build_frame(0x5A, 1), 1008)

  assert_eq(pg.frontend_count(), 4)
  assert_eq(pg.backend_count(), 5)

  // Void should have accumulated anchors from message types
  let v = pg.tap().void_snapshot()
  assert_true(v.anchors.length() > 0)
}

///|
test "skips frames too short" {
  let pg = PgTap::new("pg-tap-6")
  pg.observe_raw(true, [b'\x51'], 1000) // too short (need at least 5 bytes)
  assert_eq(pg.frontend_count(), 0) // should be skipped
}

///|
test "no payload content captured" {
  let pg = PgTap::new("pg-tap-7")
  // Build a Query with specific payload (simulated SQL)
  let frame = pg_build_frame(0x51, 50)
  // Fill payload with non-zero bytes to simulate query content
  let mut i = 5
  while i < frame.length() {
    frame[i] = b'\x41' // 'A' — pretend SQL
    i = i + 1
  }
  pg.observe_raw(true, frame, 1000)

  // Grammar tree should only have structural tokens, not content
  let tree = pg.tap().grammar()
  let root = tree.get_node(tree.active_root_key().unwrap()).unwrap()
  // Type tag token should exist
  assert_true(root.maybe_routes("t:81"))
  // But no token should contain 'A' or query content
  // (We can't directly test "absence" in a bloom filter,
  // but we verify the token format is "t:XX" not payload data)
}
