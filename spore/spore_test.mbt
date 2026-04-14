///|
test "fork mulsp produces parent-child pair" {
  let parent = @mulsp.MulspState::new("parent-001", "ratio://test", "wasm-gc", "emergent")
  // Must be Active to fork
  let attached = parent.attach("claude-opus", "root-hash-abc").unwrap()
  let active = attached.activate().unwrap()
  match active.fork("child-001", None) {
    Some((new_parent, child)) => {
      // Parent transitions to Delegated
      assert_true!(new_parent.lifecycle == @mulsp.Delegated)
      // Child starts Dormant with parent lineage
      assert_true!(child.lifecycle == @mulsp.Dormant)
      assert_eq!(child.mulsp_id, "child-001")
      assert_true!(child.is_clone())
      assert_eq!(child.parent_id(), Some("parent-001"))
      // Child inherits identity
      assert_eq!(child.genius_loci, Some("claude-opus"))
      assert_eq!(child.scope_root, Some("root-hash-abc"))
      // Child has fresh state (no residue/trail/checkpoint)
      assert_true!(child.residue_ref is None)
      assert_true!(child.trail_ref is None)
    }
    None => fail!("fork should succeed from Active state")
  }
}

///|
test "fork with scoped capabilities" {
  let parent = @mulsp.MulspState::new("p", "r", "wasm-gc", "emergent")
    .add_capability("cap-read")
    .add_capability("cap-write")
    .add_capability("cap-admin")
  let attached = parent.attach("ai", "root").unwrap()
  let active = attached.activate().unwrap()
  // Fork with only read capability
  match active.fork("c", Some(["cap-read"])) {
    Some((_parent, child)) => {
      assert_eq!(child.capability_count(), 1)
      assert_eq!(child.capability_refs[0], "cap-read")
    }
    None => fail!("scoped fork should succeed")
  }
}

///|
test "fork fails from non-Active state" {
  let dormant = @mulsp.MulspState::new("p", "r", "wasm-gc", "emergent")
  assert_true!(dormant.fork("c", None) is None)
}

///|
test "fork_as changes handler" {
  let parent = @mulsp.MulspState::new("p", "r", "wasm-gc", "emergent")
  let active = parent.attach("ai", "root").unwrap().activate().unwrap()
  match active.fork_as("c", "lsp-proxy", None) {
    Some((_parent, child)) => {
      assert_eq!(child.handler, "lsp-proxy")
    }
    None => fail!("fork_as should succeed")
  }
}

///|
test "muyata clone_as changes tier and intent" {
  let opus = @muyata.MuyataProfile::claude(
    @muyata.Opus, @muyata.Resolution, "wasm-gc", "emergent",
  )
  let haiku_scout = opus.clone_as(@muyata.Haiku, @muyata.Interposition)
  assert_true!(haiku_scout.is_scout())
  assert_true!(haiku_scout.is_observing() == false)
  assert_true!(haiku_scout.intent == @muyata.Interposition)
  // Same lineage
  assert_eq!(haiku_scout.overlay, "claude")
  assert_eq!(haiku_scout.family, "anthropic")
  // Different cost
  assert_eq!(haiku_scout.cost_weight(), 1)
  assert_eq!(opus.cost_weight(), 16)
}

///|
test "muyata clone_scoped restricts capability" {
  let opus = @muyata.MuyataProfile::claude(
    @muyata.Opus, @muyata.Resolution, "wasm-gc", "emergent",
  )
  let restricted = opus.clone_scoped(
    @muyata.Haiku, @muyata.Observation, "read-only",
  )
  assert_eq!(restricted.capability_class, "read-only")
  assert_true!(restricted.is_observing())
}

///|
test "create spore from forked identity" {
  let parent = @mulsp.MulspState::new("parent", "ratio://test", "wasm-gc", "emergent")
  let active = parent.attach("claude", "root").unwrap().activate().unwrap()
  let (_, child) = active.fork("spore-001", None).unwrap()

  let muyata = @muyata.MuyataProfile::claude(
    @muyata.Haiku, @muyata.Interposition, "wasm-gc", "emergent",
  )

  let spore = SporePack::new(child, muyata, @muyata.Interposition)
  assert_eq!(spore.spore_id, "spore-001")
  assert_eq!(spore.parent_id, "parent")
  assert_true!(spore.is_clone())
  assert_true!(spore.tier() == @muyata.Haiku)
  assert_eq!(spore.cost_weight(), 1)
  assert_true!(!spore.has_grammar())
  assert_true!(!spore.has_payload())
  assert_eq!(spore.ttl, 8)
}

///|
test "spore with grammar and payload" {
  let parent = @mulsp.MulspState::new("p", "r", "wasm-gc", "emergent")
  let active = parent.attach("ai", "root").unwrap().activate().unwrap()
  let (_, child) = active.fork("s", None).unwrap()
  let muyata = @muyata.MuyataProfile::claude(
    @muyata.Sonnet, @muyata.GrammarInfer, "wasm-gc", "emergent",
  )

  // Build a grammar tree with some protocol knowledge
  let grammar = @grammar.GrammarTree::new()
  let _ = grammar.ingest(["pg:Q", "pg:C", "pg:Z"])
  let _ = grammar.ingest(["pg:P", "pg:1", "pg:2"])

  let spore = SporePack::new(child, muyata, @muyata.GrammarInfer)
    .with_grammar(grammar)
    .with_payload([b'\xDE', b'\xAD', b'\xBE', b'\xEF'])
    .with_ttl(3)

  assert_true!(spore.has_grammar())
  assert_true!(spore.has_payload())
  assert_eq!(spore.ttl, 3)
  assert_eq!(spore.cost_weight(), 4)  // Sonnet
}

///|
test "spore relay hop decrements ttl and tracks route" {
  let parent = @mulsp.MulspState::new("p", "r", "wasm-gc", "emergent")
  let active = parent.attach("ai", "root").unwrap().activate().unwrap()
  let (_, child) = active.fork("s", None).unwrap()
  let muyata = @muyata.MuyataProfile::claude(
    @muyata.Haiku, @muyata.Interposition, "wasm-gc", "emergent",
  )

  let spore = SporePack::new(child, muyata, @muyata.Interposition).with_ttl(3)
  assert_true!(spore.can_relay())
  assert_true!(!spore.visited("node-A"))

  // Hop through node-A
  let hopped = spore.relay_hop("node-A").unwrap()
  assert_eq!(hopped.ttl, 2)
  assert_true!(hopped.visited("node-A"))
  assert_true!(!hopped.visited("node-B"))

  // Hop through node-B
  let hopped2 = hopped.relay_hop("node-B").unwrap()
  assert_eq!(hopped2.ttl, 1)
  assert_true!(hopped2.visited("node-A"))
  assert_true!(hopped2.visited("node-B"))

  // One more hop
  let hopped3 = hopped2.relay_hop("node-C").unwrap()
  assert_eq!(hopped3.ttl, 0)
  assert_true!(!hopped3.can_relay())

  // TTL exhausted — relay returns None
  assert_true!(hopped3.relay_hop("node-D") is None)
}

///|
test "spore serialization round-trip" {
  let parent = @mulsp.MulspState::new("parent-rt", "ratio://test", "wasm-gc", "emergent")
    .add_capability("cap-a")
  let active = parent.attach("claude-opus", "root-abc").unwrap().activate().unwrap()
  let (_, child) = active.fork("spore-rt", Some(["cap-a"])).unwrap()
  let muyata = @muyata.MuyataProfile::claude(
    @muyata.Haiku, @muyata.Interposition, "wasm-gc", "emergent",
  ).set_fingerprint("deadbeef01234567")

  let grammar = @grammar.GrammarTree::new()
  let _ = grammar.ingest(["pg:Q", "pg:C"])

  let void_state = @void.Void::new("spore-rt")
    .observe_bytes(1024)
    .attend("pg:Q")
    .tick()

  let spore = SporePack::new(child, muyata, @muyata.Interposition)
    .with_grammar(grammar)
    .with_void(void_state)
    .with_payload([b'\x01', b'\x02', b'\x03'])
    .with_ttl(5)

  // Hop through one node before serializing
  let hopped = spore.relay_hop("relay-node-1").unwrap()

  let bytes = hopped.to_bytes()
  match SporePack::from_bytes(bytes) {
    Some(restored) => {
      assert_eq!(restored.spore_id, "spore-rt")
      assert_eq!(restored.parent_id, "parent-rt")
      assert_eq!(restored.ttl, 4)
      assert_true!(restored.has_grammar())
      assert_true!(restored.has_payload())
      assert_eq!(restored.payload.length(), 3)
      assert_true!(restored.is_clone())
      assert_true!(restored.tier() == @muyata.Haiku)
      // Mulsp identity survived
      assert_eq!(restored.mulsp_state.genius_loci, Some("claude-opus"))
      assert_eq!(restored.mulsp_state.capability_count(), 1)
      // Muyata profile survived
      assert_eq!(restored.muyata_profile.fingerprint_commitment, Some("deadbeef01234567"))
      // Void survived
      match restored.void_state {
        Some(v) => {
          assert_true!(v.bytes_observed > 0)
          assert_true!(v.anchor_weight("pg:Q") > 0)
        }
        None => fail!("void should survive round-trip")
      }
      // Route bloom survived
      assert_true!(restored.visited("relay-node-1"))
    }
    None => fail!("spore deserialization failed")
  }
}

///|
test "from_bytes returns None on bad magic" {
  assert_true!(SporePack::from_bytes([b'\x00', b'\x00', b'\x00', b'\x00']) is None)
}

///|
test "from_bytes returns None on empty" {
  assert_true!(SporePack::from_bytes([]) is None)
}

///|
test "full spore lifecycle: observe → fork → spore → relay" {
  // 1. Parent observes Postgres traffic
  let parent_mulsp = @mulsp.MulspState::new("opus-main", "ratio://prod", "wasm-gc", "emergent")
  let active = parent_mulsp.attach("claude-opus", "tree-root").unwrap().activate().unwrap()

  // 2. Build grammar from observation
  let grammar = @grammar.GrammarTree::new()
  let _ = grammar.ingest(["pg:Q", "dir:c2s", "sz:sm"])
  let _ = grammar.ingest(["pg:C", "dir:s2c", "sz:md"])
  let _ = grammar.ingest(["pg:Z", "dir:s2c", "sz:xs"])
  let _ = grammar.seal()

  // 3. Fork as Haiku for cheap relay
  let (delegated_parent, child) = active.fork("haiku-spore-1", None).unwrap()
  assert_true!(delegated_parent.lifecycle == @mulsp.Delegated)

  let haiku_profile = @muyata.MuyataProfile::claude(
    @muyata.Haiku, @muyata.Interposition, "wasm-gc", "emergent",
  )

  // 4. Pack the spore
  let spore = SporePack::new(child, haiku_profile, @muyata.Interposition)
    .with_grammar(grammar)
    .with_payload([b'\xCA', b'\xFE'])
    .with_ttl(5)

  // 5. Relay through two hops
  let hop1 = spore.relay_hop("relay-east").unwrap()
  assert_eq!(hop1.ttl, 4)
  let hop2 = hop1.relay_hop("relay-west").unwrap()
  assert_eq!(hop2.ttl, 3)

  // 6. Arrive at destination — deserialize
  let wire = hop2.to_bytes()
  let arrived = SporePack::from_bytes(wire).unwrap()

  // 7. Validate: the spore carries its full identity + grammar + payload
  assert_eq!(arrived.mulsp_state.genius_loci, Some("claude-opus"))
  assert_true!(arrived.has_grammar())
  assert_eq!(arrived.payload[0], b'\xCA')
  assert_true!(arrived.visited("relay-east"))
  assert_true!(arrived.visited("relay-west"))
  assert_eq!(arrived.cost_weight(), 1) // Haiku = cheap
}
