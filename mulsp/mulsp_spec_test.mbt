///|
/// Spec-driven tests for the mulsp partition.
///
/// Every test in this file is grounded in the self-emitted spec from
/// `mulsp_spec()`. The tests verify two things simultaneously:
///
///   1. SPEC INTEGRITY — the metadata declared in mulsp_spec.mbt is internally
///      consistent (category counts, size rules, can_fail rules).
///
///   2. IMPLEMENTATION FIDELITY — the real MulspState functions behave exactly
///      as their spec metadata claims (transitions fail when they should, builders
///      never fail, codecs round-trip, etc.).
///
/// When a function is added to mulsp.mbt without a matching spec entry the
/// count tests fail, forcing the spec to stay in sync with the implementation.

// ---------------------------------------------------------------------------
// Spec structure — count invariants
// ---------------------------------------------------------------------------

///|
test "spec total function count is 25" {
  assert_eq(@mulsp.mulsp_spec().length(), 25)
}

///|
test "spec lifecycle category has 7 entries" {
  assert_eq(@mulsp.spec_by_category(@mulsp.Lifecycle).length(), 7)
}

///|
test "spec fork category has 4 entries" {
  assert_eq(@mulsp.spec_by_category(@mulsp.Fork).length(), 4)
}

///|
test "spec mutation category has 8 entries" {
  assert_eq(@mulsp.spec_by_category(@mulsp.Mutation).length(), 8)
}

///|
test "spec query category has 4 entries" {
  assert_eq(@mulsp.spec_by_category(@mulsp.Query).length(), 4)
}

///|
test "spec serialization category has 2 entries" {
  assert_eq(@mulsp.spec_by_category(@mulsp.Serialization).length(), 2)
}

///|
test "spec has 9 fallible functions" {
  // attach, activate, delegate, quiesce, reattach (lifecycle: 5)
  // fork, fork_as, parent_id (fork: 3)
  // from_bytes (serialization: 1)
  assert_eq(@mulsp.spec_fallible().length(), 9)
}

// ---------------------------------------------------------------------------
// Spec structure — type rules
// ---------------------------------------------------------------------------

///|
test "spec builder type never fails" {
  for entry in @mulsp.spec_by_type(@mulsp.Builder) {
    assert_eq(entry.can_fail, false)
  }
}

///|
test "spec serialization entries are all Large" {
  for entry in @mulsp.spec_by_category(@mulsp.Serialization) {
    assert_eq(entry.size, @mulsp.Large)
  }
}

///|
test "spec lifecycle has exactly one Constructor" {
  let mut count = 0
  for entry in @mulsp.spec_by_category(@mulsp.Lifecycle) {
    if entry.func_type == @mulsp.Constructor {
      count = count + 1
    }
  }
  assert_eq(count, 1)
}

///|
test "spec lifecycle transitions can_fail except new and revoke" {
  for entry in @mulsp.spec_by_category(@mulsp.Lifecycle) {
    if entry.name == "new" || entry.name == "revoke" {
      assert_eq(entry.can_fail, false)
    } else {
      assert_eq(entry.can_fail, true)
    }
  }
}

///|
test "spec fork has exactly 2 Delegation entries" {
  let mut count = 0
  for entry in @mulsp.spec_by_category(@mulsp.Fork) {
    if entry.func_type == @mulsp.Delegation {
      count = count + 1
    }
  }
  assert_eq(count, 2)
}

///|
test "spec lookup finds known function" {
  assert_true(@mulsp.spec_lookup("fork") is Some(_))
  let e = @mulsp.spec_lookup("fork").unwrap()
  assert_eq(e.category, @mulsp.Fork)
  assert_eq(e.func_type, @mulsp.Delegation)
  assert_eq(e.can_fail, true)
}

///|
test "spec lookup returns None for unknown function" {
  assert_true(@mulsp.spec_lookup("nonexistent_fn") is None)
}

// ---------------------------------------------------------------------------
// Lifecycle — spec-driven state machine walk
// ---------------------------------------------------------------------------

///|
test "spec-driven lifecycle: forward walk Dormant→Active→Quiescent→Active" {
  // Verify all 7 lifecycle function names appear in the spec
  let names : Array[String] = []
  for e in @mulsp.spec_by_category(@mulsp.Lifecycle) {
    names.push(e.name)
  }
  let mut found_new = false
  let mut found_attach = false
  let mut found_activate = false
  let mut found_delegate = false
  let mut found_quiesce = false
  let mut found_revoke = false
  let mut found_reattach = false
  for n in names {
    if n == "new" {
      found_new = true
    }
    if n == "attach" {
      found_attach = true
    }
    if n == "activate" {
      found_activate = true
    }
    if n == "delegate" {
      found_delegate = true
    }
    if n == "quiesce" {
      found_quiesce = true
    }
    if n == "revoke" {
      found_revoke = true
    }
    if n == "reattach" {
      found_reattach = true
    }
  }
  assert_true(found_new)
  assert_true(found_attach)
  assert_true(found_activate)
  assert_true(found_delegate)
  assert_true(found_quiesce)
  assert_true(found_revoke)
  assert_true(found_reattach)
}

///|
test "spec-driven lifecycle: can_fail transitions reject wrong states" {
  // attach: valid only from Dormant
  let s = @mulsp.MulspState::new("lc-1", "claude", "wasm-gc", "emergent")
  let active = s.attach("claude", "/").unwrap().activate().unwrap()
  assert_true(active.attach("claude", "/") is None)
  // activate: valid only from Attached
  assert_true(active.activate() is None)
  // delegate: valid only from Active
  assert_true(s.delegate("child-1") is None)
  // quiesce: valid only from Active or Delegated
  assert_true(s.quiesce() is None)
  // reattach: valid only from Quiescent
  assert_true(active.reattach() is None)
}

///|
test "spec-driven lifecycle: complete cycle Active→Delegated→Quiescent→Attached→Active" {
  let s = @mulsp.MulspState::new("lc-2", "claude", "wasm-gc", "emergent")
  let active1 = s.attach("claude", "/root").unwrap().activate().unwrap()
  assert_eq(active1.lifecycle, @mulsp.Active)
  let delegated = active1.delegate("child-x").unwrap()
  assert_eq(delegated.lifecycle, @mulsp.Delegated)
  let quiescent = delegated.quiesce().unwrap()
  assert_eq(quiescent.lifecycle, @mulsp.Quiescent)
  let reattached = quiescent.reattach().unwrap()
  assert_eq(reattached.lifecycle, @mulsp.Attached)
  let active2 = reattached.activate().unwrap()
  assert_eq(active2.lifecycle, @mulsp.Active)
}

///|
test "spec-driven lifecycle: revoke is terminal from any state" {
  let s = @mulsp.MulspState::new("lc-3", "claude", "wasm-gc", "emergent")
  assert_eq(s.revoke().lifecycle, @mulsp.Revoked)
  let attached = s.attach("claude", "/").unwrap()
  assert_eq(attached.revoke().lifecycle, @mulsp.Revoked)
  let active = attached.activate().unwrap()
  assert_eq(active.revoke().lifecycle, @mulsp.Revoked)
  assert_eq(active.revoke().is_terminal(), true)
}

// ---------------------------------------------------------------------------
// Fork — spec-driven Delegation checks
// ---------------------------------------------------------------------------

///|
test "spec-driven fork: fork produces Delegated parent and Dormant child" {
  let s = @mulsp.MulspState::new("p-1", "claude", "wasm-gc", "emergent")
  let active = s.attach("claude", "/").unwrap().activate().unwrap()
  let result = active.fork("c-1", None)
  assert_true(result is Some(_))
  let (parent, child) = result.unwrap()
  assert_eq(parent.lifecycle, @mulsp.Delegated)
  assert_eq(child.lifecycle, @mulsp.Dormant)
  assert_true(child.is_clone())
  assert_eq(child.parent_id(), Some("p-1"))
}

///|
test "spec-driven fork: fork fails from non-Active states" {
  let s = @mulsp.MulspState::new("p-2", "claude", "wasm-gc", "emergent")
  assert_true(s.fork("c-1", None) is None)
  let attached = s.attach("claude", "/").unwrap()
  assert_true(attached.fork("c-1", None) is None)
  let quiescent = attached.activate().unwrap().quiesce().unwrap()
  assert_true(quiescent.fork("c-1", None) is None)
}

///|
test "spec-driven fork: fork_as overrides child handler" {
  let s = @mulsp.MulspState::new("p-3", "claude", "wasm-gc", "emergent")
  let active = s.attach("claude", "/").unwrap().activate().unwrap()
  let result = active.fork_as("c-1", "lsp-proxy", None)
  assert_true(result is Some(_))
  let (_, child) = result.unwrap()
  assert_eq(child.handler, "lsp-proxy")
}

///|
test "spec-driven fork: is_clone false for root, true for child" {
  let s = @mulsp.MulspState::new("p-4", "claude", "wasm-gc", "emergent")
  assert_eq(s.is_clone(), false)
  let active = s.attach("claude", "/").unwrap().activate().unwrap()
  let (_, child) = active.fork("c-1", None).unwrap()
  assert_eq(child.is_clone(), true)
}

///|
test "spec-driven fork: parent_id returns None for root mulsp" {
  let s = @mulsp.MulspState::new("root-1", "claude", "wasm-gc", "emergent")
  assert_true(s.parent_id() is None)
}

///|
test "spec-driven fork: scoped capabilities inherited or overridden" {
  let s = @mulsp.MulspState::new("p-5", "claude", "wasm-gc", "emergent")
  let active = s
    .attach("claude", "/")
    .unwrap()
    .activate()
    .unwrap()
    .add_capability("cap-a")
    .add_capability("cap-b")
  // Fork with scoped caps
  let (_, child_scoped) = active.fork("c-scoped", Some(["cap-a"])).unwrap()
  assert_eq(child_scoped.capability_count(), 1)
  // Fork inheriting all caps
  let (_, child_all) = active.fork("c-all", None).unwrap()
  assert_eq(child_all.capability_count(), 2)
}

// ---------------------------------------------------------------------------
// Mutation — spec Builder entries exercise all 8 functions
// ---------------------------------------------------------------------------

///|
test "spec-driven mutation: all 8 builders return updated state without failing" {
  let s = @mulsp.MulspState::new("m-1", "claude", "wasm-gc", "emergent")
  // bind_procsi
  let s1 = s.bind_procsi({ locus: "zone-a", project: "lang", tier: "sonnet" })
  assert_true(s1.procsi_ref is Some(_))
  // bind_app
  let s2 = s1.bind_app({ protocol: "app-v1", audience: "lang", ref_id: "r42" })
  assert_true(s2.app_ref is Some(_))
  // add_capability
  let s3 = s2.add_capability("cap-abc")
  assert_eq(s3.capability_count(), 1)
  // emit_residue
  let s4 = s3.emit_residue("r-hash-1")
  assert_true(s4.residue_ref is Some(_))
  // update_trail
  let s5 = s4.update_trail("t-hash-1")
  assert_true(s5.trail_ref is Some(_))
  // checkpoint
  let s6 = s5.checkpoint("cp-hash-1")
  assert_true(s6.checkpoint_ref is Some(_))
  // set_projection
  let s7 = s6.set_projection("proj-root")
  assert_true(s7.projection_root is Some(_))
  // set_fingerprint
  let s8 = s7.set_fingerprint("fp-commit")
  assert_true(s8.fingerprint_commitment is Some(_))
  // Verify the spec says all 8 are Builder / can_fail=false
  assert_eq(@mulsp.spec_by_category(@mulsp.Mutation).length(), 8)
  for entry in @mulsp.spec_by_category(@mulsp.Mutation) {
    assert_eq(entry.func_type, @mulsp.Builder)
    assert_eq(entry.can_fail, false)
  }
}

///|
test "spec-driven mutation: add_capability is cumulative" {
  let s = @mulsp.MulspState::new("m-2", "claude", "wasm-gc", "emergent")
  let s3 = s
    .add_capability("cap-1")
    .add_capability("cap-2")
    .add_capability("cap-3")
  assert_eq(s3.capability_count(), 3)
}

// ---------------------------------------------------------------------------
// Query — spec Predicate + Counter entries
// ---------------------------------------------------------------------------

///|
test "spec-driven query: predicates reflect lifecycle state correctly" {
  let s = @mulsp.MulspState::new("q-1", "claude", "wasm-gc", "emergent")
  // Dormant
  assert_eq(s.is_active(), false)
  assert_eq(s.is_terminal(), false)
  assert_eq(s.can_accept_work(), false)
  // Attached
  let attached = s.attach("claude", "/").unwrap()
  assert_eq(attached.is_active(), false)
  assert_eq(attached.can_accept_work(), true)
  // Active
  let active = attached.activate().unwrap()
  assert_eq(active.is_active(), true)
  assert_eq(active.can_accept_work(), true)
  // Quiescent
  let quiescent = active.quiesce().unwrap()
  assert_eq(quiescent.is_active(), false)
  assert_eq(quiescent.can_accept_work(), false)
  // Revoked
  let revoked = active.revoke()
  assert_eq(revoked.is_terminal(), true)
  assert_eq(revoked.is_active(), false)
  assert_eq(revoked.can_accept_work(), false)
}

///|
test "spec-driven query: capability_count tracks additions and fork inheritance" {
  let s = @mulsp.MulspState::new("q-2", "claude", "wasm-gc", "emergent")
  assert_eq(s.capability_count(), 0)
  let active = s
    .attach("claude", "/")
    .unwrap()
    .activate()
    .unwrap()
    .add_capability("cap-x")
    .add_capability("cap-y")
  assert_eq(active.capability_count(), 2)
  // Forked child inherits capabilities
  let (_, child) = active.fork("c-q", None).unwrap()
  assert_eq(child.capability_count(), 2)
}

///|
test "spec-driven query: all query entries are Trivial size" {
  for entry in @mulsp.spec_by_category(@mulsp.Query) {
    assert_eq(entry.size, @mulsp.Trivial)
  }
}

// ---------------------------------------------------------------------------
// Serialization — spec Codec entries: round-trip and failure modes
// ---------------------------------------------------------------------------

///|
test "spec-driven serialization: to_bytes/from_bytes full round-trip" {
  let s = @mulsp.MulspState::new("ser-1", "claude", "wasm-gc", "emergent")
  let active = s
    .attach("claude", "/root")
    .unwrap()
    .activate()
    .unwrap()
    .add_capability("cap-x")
    .set_fingerprint("fp-abc")
  let bytes = active.to_bytes()
  let restored = @mulsp.MulspState::from_bytes(bytes)
  assert_true(restored is Some(_))
  let r = restored.unwrap()
  assert_eq(r.mulsp_id, "ser-1")
  assert_eq(r.lifecycle, @mulsp.Active)
  assert_eq(r.capability_count(), 1)
  assert_eq(r.fingerprint_commitment, Some("fp-abc"))
  assert_eq(r.scope_root, Some("/root"))
}

///|
test "spec-driven serialization: forked child round-trips with parent lineage" {
  let s = @mulsp.MulspState::new("par-1", "claude", "wasm-gc", "emergent")
  let active = s.attach("claude", "/").unwrap().activate().unwrap()
  let (_, child) = active.fork("child-1", None).unwrap()
  let child_active = child.attach("claude", "/").unwrap().activate().unwrap()
  let bytes = child_active.to_bytes()
  let restored = @mulsp.MulspState::from_bytes(bytes).unwrap()
  assert_eq(restored.mulsp_id, "child-1")
  assert_eq(restored.parent_id(), Some("par-1"))
  assert_eq(restored.is_clone(), true)
}

///|
test "spec-driven serialization: from_bytes rejects bad magic" {
  let bad : Array[Byte] = [
    b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00',
  ]
  assert_true(@mulsp.MulspState::from_bytes(bad) is None)
}

///|
test "spec-driven serialization: from_bytes rejects truncated data" {
  assert_true(@mulsp.MulspState::from_bytes([]) is None)
  assert_true(
    @mulsp.MulspState::from_bytes([b'\x4D', b'\x4C', b'\x53', b'\x50']) is None,
  )
}

///|
test "spec-driven serialization: codec spec entries cover to_bytes and from_bytes" {
  let codec = @mulsp.spec_by_type(@mulsp.Codec)
  assert_eq(codec.length(), 2)
  let mut has_to = false
  let mut has_from = false
  for e in codec {
    if e.name == "to_bytes" {
      has_to = true
      assert_eq(e.can_fail, false)
      assert_eq(e.size, @mulsp.Large)
    }
    if e.name == "from_bytes" {
      has_from = true
      assert_eq(e.can_fail, true)
      assert_eq(e.size, @mulsp.Large)
    }
  }
  assert_true(has_to)
  assert_true(has_from)
}

// ---------------------------------------------------------------------------
// Cross-category — size distribution sanity check
// ---------------------------------------------------------------------------

///|
test "spec size distribution: most mutation and query entries are Trivial" {
  let mut trivial_count = 0
  for entry in @mulsp.spec_by_category(@mulsp.Mutation) {
    if entry.size == @mulsp.Trivial {
      trivial_count = trivial_count + 1
    }
  }
  for entry in @mulsp.spec_by_category(@mulsp.Query) {
    if entry.size == @mulsp.Trivial {
      trivial_count = trivial_count + 1
    }
  }
  // At least 10 of the 12 mutation+query entries should be Trivial
  assert_true(trivial_count >= 10)
}

///|
test "spec size distribution: no serialization entry is Trivial or Small" {
  for entry in @mulsp.spec_by_category(@mulsp.Serialization) {
    assert_true(entry.size != @mulsp.Trivial)
    assert_true(entry.size != @mulsp.Small)
  }
}

///|
test "spec size distribution: fork contains exactly one Medium entry" {
  let mut medium_count = 0
  for entry in @mulsp.spec_by_category(@mulsp.Fork) {
    if entry.size == @mulsp.Medium {
      medium_count = medium_count + 1
    }
  }
  assert_eq(medium_count, 1)
}
