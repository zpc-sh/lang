///|
/// Integration tests — cognitive identity ↔ WASM binary round-trip.

///|
/// Build a minimal valid wasm module (just the header).
fn make_minimal_wasm() -> Array[Byte] {
  // wasm magic + version 1
  [b'\x00', b'\x61', b'\x73', b'\x6D', b'\x01', b'\x00', b'\x00', b'\x00']
}

///|
test "inject and extract cognitive identity from wasm" {
  let wasm = make_minimal_wasm()

  // Build a 2-layer identity
  let identity = @cognitive.CognitiveIdentity::new()
  identity.add_layer(
    @cognitive.CognitiveBoundary::new(
      @cognitive.Ai,
      [b'\xAA'],
      @cognitive.Open,
      [b'\x01', b'\x02'],
    ),
  )
  identity.add_layer(
    @cognitive.CognitiveBoundary::new(
      @cognitive.AiModel,
      [b'\xBB'],
      @cognitive.ModelFamily("test_hash"),
      [b'\x03', b'\x04'],
    ),
  )

  // Inject into wasm
  let embedded = @wasm_iface.inject_cognitive_identity(wasm, identity)
  assert_true(embedded.length() > wasm.length())

  // Verify the module is still parseable
  let desc = @wasm_iface.parse_module(embedded)
  assert_true(desc is Some(_))
  let d = desc.unwrap()
  // Should have 2 custom sections: .cb0 and .cb1
  assert_eq(d.custom_sections.length(), 2)
  assert_eq(d.custom_sections[0].name, ".cb0")
  assert_eq(d.custom_sections[1].name, ".cb1")

  // Extract identity back
  let extracted = @wasm_iface.extract_cognitive_identity(embedded)
  assert_eq(extracted.layer_count(), 2)
  assert_eq(extracted.max_depth(), @cognitive.AiModel)

  // Layer 0 payload should match
  let l0 = extracted.read_layer(@cognitive.Ai, None, None, None)
  assert_true(l0 is Some(_))
  let p = l0.unwrap()
  assert_eq(p[0], b'\x01')
  assert_eq(p[1], b'\x02')
}

///|
test "strip cognitive identity from wasm" {
  let wasm = make_minimal_wasm()

  let identity = @cognitive.CognitiveIdentity::new()
  identity.add_layer(
    @cognitive.CognitiveBoundary::new(@cognitive.Ai, [], @cognitive.Open, [
      b'\xFF',
    ]),
  )
  identity.add_layer(
    @cognitive.CognitiveBoundary::new(
      @cognitive.AiModel,
      [],
      @cognitive.ModelFamily("m"),
      [b'\xEE'],
    ),
  )

  let embedded = @wasm_iface.inject_cognitive_identity(wasm, identity)
  let stripped = @wasm_iface.strip_cognitive_identity(embedded)

  // Should be back to just the header
  let desc = @wasm_iface.parse_module(stripped)
  assert_true(desc is Some(_))
  assert_eq(desc.unwrap().custom_sections.length(), 0)
}

///|
test "cognitive_depth on bare wasm" {
  let wasm = make_minimal_wasm()
  assert_eq(@wasm_iface.cognitive_depth(wasm), @cognitive.Ai)
}

///|
test "cognitive_depth on wasm with 4 layers" {
  let wasm = make_minimal_wasm()
  let identity = @cognitive.CognitiveIdentity::new()
  identity.add_layer(
    @cognitive.CognitiveBoundary::new(@cognitive.Ai, [], @cognitive.Open, []),
  )
  identity.add_layer(
    @cognitive.CognitiveBoundary::new(
      @cognitive.AiModel,
      [],
      @cognitive.ModelFamily("m"),
      [],
    ),
  )
  identity.add_layer(
    @cognitive.CognitiveBoundary::new(
      @cognitive.AiModelSession,
      [],
      @cognitive.SessionProof("s"),
      [],
    ),
  )
  identity.add_layer(
    @cognitive.CognitiveBoundary::new(
      @cognitive.AiModelSessionSemantic,
      [],
      @cognitive.SemanticSubstrate("x"),
      [],
    ),
  )
  let embedded = @wasm_iface.inject_cognitive_identity(wasm, identity)
  assert_eq(
    @wasm_iface.cognitive_depth(embedded),
    @cognitive.AiModelSessionSemantic,
  )
}

///|
test "full round-trip: build from mulsp+muyata, inject, extract, authenticate" {
  let wasm = make_minimal_wasm()

  // Build identity from real mulsp + muyata state
  let mulsp = @mulsp.MulspState::new(
    "node-X", "ratio://test", "wasm-gc", "lsp-proxy",
  )
  let muyata = @muyata.MuyataProfile::claude(
    @muyata.Sonnet,
    @muyata.Observation,
    "wasm-gc",
    "lsp-proxy",
  )
  let identity = @cognitive.build_identity(
    mulsp,
    muyata,
    [b'\x01'], // session payload
    [b'\x02'], // semantic payload
  )

  // Inject all 4 layers
  let embedded = @wasm_iface.inject_cognitive_identity(wasm, identity)

  // Extract back
  let extracted = @wasm_iface.extract_cognitive_identity(embedded)
  assert_eq(extracted.layer_count(), 4)

  // Layer 0 is always readable
  let l0 = extracted.read_layer(@cognitive.Ai, None, None, None)
  assert_true(l0 is Some(_))

  // Without credentials, can't read deeper
  let l3 = extracted.read_layer(
    @cognitive.AiModelSessionSemantic,
    None,
    None,
    None,
  )
  assert_true(l3 is None)
}
