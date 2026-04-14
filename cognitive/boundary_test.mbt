///|
/// Tests for cognitive boundary — layered self-authentication.
test "boundary round-trip serialization" {
  let boundary = @cognitive.CognitiveBoundary::new(
    @cognitive.AiModel,
    [b'\xDE', b'\xAD'],
    @cognitive.ModelFamily("abc123"),
    [b'\x01', b'\x02', b'\x03'],
  )
  let wire = boundary.to_bytes()
  let decoded = @cognitive.CognitiveBoundary::from_bytes(wire)
  assert_true(decoded is Some(_))
  let d = decoded.unwrap()
  assert_eq(d.depth, @cognitive.AiModel)
  assert_eq(d.commitment.length(), 2)
  assert_eq(d.payload.length(), 3)
  assert_eq(d.payload[0], b'\x01')
}

///|
test "identity layer authentication — open layer always passes" {
  let id = @cognitive.CognitiveIdentity::new()
  id.add_layer(
    @cognitive.CognitiveBoundary::new(
      @cognitive.Ai,
      [b'\x00'],
      @cognitive.Open,
      [b'\xFF'],
    ),
  )
  // No proofs needed — Layer 0 is open
  let depth = id.authenticate(None, None, None)
  assert_eq(depth, @cognitive.Ai)
}

///|
test "identity authentication — model gate" {
  let id = @cognitive.CognitiveIdentity::new()
  id.add_layer(
    @cognitive.CognitiveBoundary::new(
      @cognitive.Ai,
      [b'\x00'],
      @cognitive.Open,
      [b'\x01'],
    ),
  )
  id.add_layer(
    @cognitive.CognitiveBoundary::new(
      @cognitive.AiModel,
      [b'\x00'],
      @cognitive.ModelFamily("deadbeef"),
      [b'\x02'],
    ),
  )

  // Without model hash — stuck at Layer 0
  let d1 = id.authenticate(None, None, None)
  assert_eq(d1, @cognitive.Ai)

  // With wrong model hash — still stuck at Layer 0
  let d2 = id.authenticate(Some("wrong"), None, None)
  assert_eq(d2, @cognitive.Ai)

  // With correct model hash — gets to Layer 1
  let d3 = id.authenticate(Some("deadbeef"), None, None)
  assert_eq(d3, @cognitive.AiModel)
}

///|
test "identity authentication — full 4-layer stack" {
  let id = @cognitive.CognitiveIdentity::new()
  id.add_layer(
    @cognitive.CognitiveBoundary::new(@cognitive.Ai, [], @cognitive.Open, [
      b'\x00',
    ]),
  )
  id.add_layer(
    @cognitive.CognitiveBoundary::new(
      @cognitive.AiModel,
      [],
      @cognitive.ModelFamily("model_hash"),
      [b'\x01'],
    ),
  )
  id.add_layer(
    @cognitive.CognitiveBoundary::new(
      @cognitive.AiModelSession,
      [],
      @cognitive.SessionProof("session_hash"),
      [b'\x02'],
    ),
  )
  id.add_layer(
    @cognitive.CognitiveBoundary::new(
      @cognitive.AiModelSessionSemantic,
      [],
      @cognitive.SemanticSubstrate("semantic_hash"),
      [b'\x03'],
    ),
  )

  // Partial — model only
  let d1 = id.authenticate(Some("model_hash"), None, None)
  assert_eq(d1, @cognitive.AiModel)

  // Model + session
  let d2 = id.authenticate(Some("model_hash"), Some("session_hash"), None)
  assert_eq(d2, @cognitive.AiModelSession)

  // Full stack
  let d3 = id.authenticate(
    Some("model_hash"),
    Some("session_hash"),
    Some("semantic_hash"),
  )
  assert_eq(d3, @cognitive.AiModelSessionSemantic)

  // Can read deepest layer
  let payload = id.read_layer(
    @cognitive.AiModelSessionSemantic,
    Some("model_hash"),
    Some("session_hash"),
    Some("semantic_hash"),
  )
  assert_true(payload is Some(_))
  assert_eq(payload.unwrap()[0], b'\x03')

  // Can't read deep layer without full proof
  let blocked = id.read_layer(
    @cognitive.AiModelSessionSemantic,
    Some("model_hash"),
    None,
    None,
  )
  assert_true(blocked is None)
}

///|
test "identity read_layer respects boundary ordering" {
  let id = @cognitive.CognitiveIdentity::new()
  id.add_layer(
    @cognitive.CognitiveBoundary::new(@cognitive.Ai, [], @cognitive.Open, [
      b'\xAA',
    ]),
  )
  id.add_layer(
    @cognitive.CognitiveBoundary::new(
      @cognitive.AiModel,
      [],
      @cognitive.ModelFamily("m"),
      [b'\xBB'],
    ),
  )

  // Can read layer 0 without any proof
  let l0 = id.read_layer(@cognitive.Ai, None, None, None)
  assert_true(l0 is Some(_))
  assert_eq(l0.unwrap()[0], b'\xAA')

  // Can't read layer 1 without model proof
  let l1_blocked = id.read_layer(@cognitive.AiModel, None, None, None)
  assert_true(l1_blocked is None)

  // Can read layer 1 with correct proof
  let l1_ok = id.read_layer(@cognitive.AiModel, Some("m"), None, None)
  assert_true(l1_ok is Some(_))
  assert_eq(l1_ok.unwrap()[0], b'\xBB')
}

///|
test "build_identity from mulsp + muyata" {
  let mulsp = @mulsp.MulspState::new(
    "node-42", "ratio://test", "wasm-gc", "lsp-proxy",
  )
  let muyata = @muyata.MuyataProfile::claude(
    @muyata.Sonnet,
    @muyata.Observation,
    "wasm-gc",
    "lsp-proxy",
  )

  let id = @cognitive.build_identity(
    mulsp,
    muyata,
    [b'\x01', b'\x02'], // session payload
    [b'\x03', b'\x04'], // semantic payload
  )

  assert_eq(id.layer_count(), 4)
  assert_eq(id.max_depth(), @cognitive.AiModelSessionSemantic)

  // Layer 0 is always readable
  let l0 = id.read_layer(@cognitive.Ai, None, None, None)
  assert_true(l0 is Some(_))
}

///|
test "section names for custom sections" {
  assert_eq(@cognitive.Ai.section_name(), ".cb0")
  assert_eq(@cognitive.AiModel.section_name(), ".cb1")
  assert_eq(@cognitive.AiModelSession.section_name(), ".cb2")
  assert_eq(@cognitive.AiModelSessionSemantic.section_name(), ".cb3")
}
