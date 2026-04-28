///|
/// Tests for loci/claude — Haiku stigmergy via Loci cave storage.

// ---------------------------------------------------------------------------
// StigmaEntry serialization
// ---------------------------------------------------------------------------

///|
test "stigma entry round-trip" {
  let entry = @claude.StigmaEntry::fresh("cave/store", 12, 3, 5000)
  let bytes = entry.to_bytes()
  let restored = @claude.StigmaEntry::from_bytes(bytes)
  assert_true(restored is Some(_))
  let r = restored.unwrap()
  assert_eq(r.anchor, "cave/store")
  assert_eq(r.total_weight, 12)
  assert_eq(r.contributor_count, 1)
  assert_eq(r.last_epoch, 3)
  assert_eq(r.last_timestamp, 5000)
}

///|
test "stigma entry accrete accumulates weight" {
  let entry = @claude.StigmaEntry::fresh("mulsp/lifecycle", 10, 1, 100)
  let entry2 = entry.accrete(5, 2, 200)
  let entry3 = entry2.accrete(8, 1, 300)
  assert_eq(entry3.total_weight, 23)
  assert_eq(entry3.contributor_count, 3)
  assert_eq(entry3.last_epoch, 2)
  assert_eq(entry3.last_timestamp, 300)
}

///|
test "stigma entry from_bytes rejects bad magic" {
  let bad : Array[Byte] = [b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00',
    b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00',
    b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00']
  assert_true(@claude.StigmaEntry::from_bytes(bad) is None)
}

///|
test "stigma entry from_bytes rejects too-short data" {
  assert_true(@claude.StigmaEntry::from_bytes([]) is None)
  assert_true(@claude.StigmaEntry::from_bytes([b'\x53', b'\x54', b'\x45']) is None)
}

// ---------------------------------------------------------------------------
// LociStigmergy
// ---------------------------------------------------------------------------

///|
test "loci stigmergy deposit and read_anchor" {
  let cave = @cave.CaveStore::standard()
  let stigmergy = @claude.LociStigmergy::new(cave, "node-1")
  let r1 = @emergent.Residue::new("node-1", 0, "yata/void", 10, 1000)
  stigmergy.deposit(r1)
  let entry = stigmergy.read_anchor("yata/void")
  assert_true(entry is Some(_))
  let e = entry.unwrap()
  assert_eq(e.anchor, "yata/void")
  assert_eq(e.total_weight, 10)
  assert_eq(e.contributor_count, 1)
}

///|
test "loci stigmergy merges multiple deposits for same anchor" {
  let cave = @cave.CaveStore::standard()
  let stigmergy = @claude.LociStigmergy::new(cave, "node-1")
  stigmergy.deposit(@emergent.Residue::new("n1", 0, "mulsp", 5, 100))
  stigmergy.deposit(@emergent.Residue::new("n2", 1, "mulsp", 7, 200))
  stigmergy.deposit(@emergent.Residue::new("n1", 2, "mulsp", 3, 300))
  let entry = stigmergy.read_anchor("mulsp").unwrap()
  assert_eq(entry.total_weight, 15)
  assert_eq(entry.contributor_count, 3)
  assert_eq(entry.last_timestamp, 300)
}

///|
test "loci stigmergy all_anchors lists deposited anchors" {
  let cave = @cave.CaveStore::standard()
  let stigmergy = @claude.LociStigmergy::new(cave, "node-1")
  stigmergy.deposit(@emergent.Residue::new("n", 0, "alpha", 1, 0))
  stigmergy.deposit(@emergent.Residue::new("n", 1, "beta", 2, 0))
  stigmergy.deposit(@emergent.Residue::new("n", 2, "gamma", 3, 0))
  let anchors = stigmergy.all_anchors()
  assert_eq(anchors.length(), 3)
}

///|
test "loci stigmergy top_anchors sorts by weight descending" {
  let cave = @cave.CaveStore::standard()
  let stigmergy = @claude.LociStigmergy::new(cave, "node-1")
  stigmergy.deposit(@emergent.Residue::new("n", 0, "low", 2, 0))
  stigmergy.deposit(@emergent.Residue::new("n", 1, "high", 20, 0))
  stigmergy.deposit(@emergent.Residue::new("n", 2, "mid", 10, 0))
  let top = stigmergy.top_anchors(3)
  assert_eq(top.length(), 3)
  assert_eq(top[0].anchor, "high")
  assert_eq(top[1].anchor, "mid")
  assert_eq(top[2].anchor, "low")
}

///|
test "loci stigmergy top_anchors respects n limit" {
  let cave = @cave.CaveStore::standard()
  let stigmergy = @claude.LociStigmergy::new(cave, "node-1")
  stigmergy.deposit(@emergent.Residue::new("n", 0, "a1", 5, 0))
  stigmergy.deposit(@emergent.Residue::new("n", 1, "a2", 3, 0))
  stigmergy.deposit(@emergent.Residue::new("n", 2, "a3", 1, 0))
  let top = stigmergy.top_anchors(2)
  assert_eq(top.length(), 2)
  assert_eq(top[0].anchor, "a1")
  assert_eq(top[1].anchor, "a2")
}

// ---------------------------------------------------------------------------
// ClaudeOrchestrator construction
// ---------------------------------------------------------------------------

///|
test "orchestrator rejects haiku tier" {
  let cave = @cave.CaveStore::standard()
  let mulsp = @mulsp.MulspState::new("h-1", "claude", "wasm-gc", "emergent")
  let mulsp2 = mulsp.attach("claude", "/").unwrap()
  let mulsp3 = mulsp2.activate().unwrap()
  let muyata = @muyata.MuyataProfile::claude(
    @muyata.Haiku,
    @muyata.Delegation,
    "wasm-gc",
    "emergent",
  )
  assert_true(@claude.ClaudeOrchestrator::new(mulsp3, muyata, cave) is None)
}

///|
test "orchestrator rejects non-active mulsp" {
  let cave = @cave.CaveStore::standard()
  let mulsp = @mulsp.MulspState::new("s-1", "claude", "wasm-gc", "emergent")
  let muyata = @muyata.MuyataProfile::claude(
    @muyata.Sonnet,
    @muyata.Delegation,
    "wasm-gc",
    "emergent",
  )
  assert_true(@claude.ClaudeOrchestrator::new(mulsp, muyata, cave) is None)
}

///|
test "orchestrator accepts sonnet tier" {
  let cave = @cave.CaveStore::standard()
  let mulsp = @mulsp.MulspState::new("s-1", "claude", "wasm-gc", "emergent")
  let mulsp2 = mulsp.attach("claude", "/").unwrap()
  let mulsp3 = mulsp2.activate().unwrap()
  let muyata = @muyata.MuyataProfile::claude(
    @muyata.Sonnet,
    @muyata.Delegation,
    "wasm-gc",
    "emergent",
  )
  let orch = @claude.ClaudeOrchestrator::new(mulsp3, muyata, cave)
  assert_true(orch is Some(_))
}

///|
test "orchestrator accepts opus tier" {
  let cave = @cave.CaveStore::standard()
  let mulsp = @mulsp.MulspState::new("o-1", "claude", "wasm-gc", "emergent")
  let mulsp2 = mulsp.attach("claude", "/").unwrap()
  let mulsp3 = mulsp2.activate().unwrap()
  let muyata = @muyata.MuyataProfile::claude(
    @muyata.Opus,
    @muyata.Delegation,
    "wasm-gc",
    "emergent",
  )
  let orch = @claude.ClaudeOrchestrator::new(mulsp3, muyata, cave)
  assert_true(orch is Some(_))
}

// ---------------------------------------------------------------------------
// Spawning Haiku scouts
// ---------------------------------------------------------------------------

///|
test "orchestrator spawns haiku scout" {
  let cave = @cave.CaveStore::standard()
  let mulsp = @mulsp.MulspState::new("s-1", "claude", "wasm-gc", "emergent")
  let mulsp2 = mulsp.attach("claude", "/").unwrap()
  let mulsp3 = mulsp2.activate().unwrap()
  let muyata = @muyata.MuyataProfile::claude(
    @muyata.Sonnet,
    @muyata.Delegation,
    "wasm-gc",
    "emergent",
  )
  let orch = @claude.ClaudeOrchestrator::new(mulsp3, muyata, cave).unwrap()
  let scout = orch.spawn_haiku(@muyata.Observation)
  assert_true(scout is Some(_))
  let s = scout.unwrap()
  assert_true(s.is_active())
  assert_true(s.muyata.is_scout())
  assert_eq(orch.total_scout_count(), 1)
}

///|
test "haiku scout is child of orchestrator mulsp" {
  let cave = @cave.CaveStore::standard()
  let mulsp = @mulsp.MulspState::new("s-1", "claude", "wasm-gc", "emergent")
  let mulsp2 = mulsp.attach("claude", "/").unwrap()
  let mulsp3 = mulsp2.activate().unwrap()
  let muyata = @muyata.MuyataProfile::claude(
    @muyata.Sonnet,
    @muyata.Delegation,
    "wasm-gc",
    "emergent",
  )
  let orch = @claude.ClaudeOrchestrator::new(mulsp3, muyata, cave).unwrap()
  let scout = orch.spawn_haiku(@muyata.Observation).unwrap()
  // Scout ID contains orchestrator's mulsp_id as prefix
  assert_true(scout.scout_id().length() > 0)
  // Scout snapshot is in loci
  let keys = cave.loci_keys()
  let mut found = false
  for k in keys {
    if k == "m:" + scout.scout_id() {
      found = true
    }
  }
  assert_true(found)
}

///|
test "orchestrator can spawn multiple scouts" {
  let cave = @cave.CaveStore::standard()
  let mulsp = @mulsp.MulspState::new("s-1", "claude", "wasm-gc", "emergent")
  let mulsp2 = mulsp.attach("claude", "/").unwrap()
  let mulsp3 = mulsp2.activate().unwrap()
  let muyata = @muyata.MuyataProfile::claude(
    @muyata.Sonnet,
    @muyata.Delegation,
    "wasm-gc",
    "emergent",
  )
  let orch = @claude.ClaudeOrchestrator::new(mulsp3, muyata, cave).unwrap()
  let s1 = orch.spawn_haiku(@muyata.Observation)
  let s2 = orch.spawn_haiku(@muyata.GrammarInfer)
  let s3 = orch.spawn_haiku(@muyata.Audit)
  assert_true(s1 is Some(_))
  assert_true(s2 is Some(_))
  assert_true(s3 is Some(_))
  assert_eq(orch.total_scout_count(), 3)
}

// ---------------------------------------------------------------------------
// Stigmergy through observe → hot_anchors
// ---------------------------------------------------------------------------

///|
test "scout deposits to loci orchestrator reads hot anchors" {
  let cave = @cave.CaveStore::standard()
  let mulsp = @mulsp.MulspState::new("s-1", "claude", "wasm-gc", "emergent")
  let mulsp2 = mulsp.attach("claude", "/").unwrap()
  let mulsp3 = mulsp2.activate().unwrap()
  let muyata = @muyata.MuyataProfile::claude(
    @muyata.Sonnet,
    @muyata.Delegation,
    "wasm-gc",
    "emergent",
  )
  let orch = @claude.ClaudeOrchestrator::new(mulsp3, muyata, cave).unwrap()
  let scout = orch.spawn_haiku(@muyata.Observation).unwrap()
  assert_true(scout.observe("cave/storage", 10, 1000))
  assert_true(scout.observe("cave/storage", 5, 2000))
  assert_true(scout.observe("mulsp/lifecycle", 8, 3000))
  let anchors = orch.hot_anchors(2)
  assert_eq(anchors.length(), 2)
  assert_eq(anchors[0].anchor, "cave/storage")
  assert_eq(anchors[0].total_weight, 15)
  assert_eq(anchors[0].contributor_count, 2)
  assert_eq(anchors[1].anchor, "mulsp/lifecycle")
  assert_eq(anchors[1].total_weight, 8)
}

///|
test "multiple scouts converge on same anchor" {
  let cave = @cave.CaveStore::standard()
  let mulsp = @mulsp.MulspState::new("o-1", "claude", "wasm-gc", "emergent")
  let mulsp2 = mulsp.attach("claude", "/").unwrap()
  let mulsp3 = mulsp2.activate().unwrap()
  let muyata = @muyata.MuyataProfile::claude(
    @muyata.Opus,
    @muyata.Delegation,
    "wasm-gc",
    "emergent",
  )
  let orch = @claude.ClaudeOrchestrator::new(mulsp3, muyata, cave).unwrap()
  let s1 = orch.spawn_haiku(@muyata.Observation).unwrap()
  let s2 = orch.spawn_haiku(@muyata.Observation).unwrap()
  let s3 = orch.spawn_haiku(@muyata.GrammarInfer).unwrap()
  // All three converge on "loci/partition"
  let _ = s1.observe("loci/partition", 6, 100)
  let _ = s2.observe("loci/partition", 4, 200)
  let _ = s3.observe("loci/partition", 9, 300)
  // s1 and s2 also notice "muyata/tier"
  let _ = s1.observe("muyata/tier", 3, 150)
  let _ = s2.observe("muyata/tier", 3, 250)
  let top = orch.hot_anchors(2)
  assert_eq(top[0].anchor, "loci/partition")
  assert_eq(top[0].total_weight, 19)
  assert_eq(top[0].contributor_count, 3)
  assert_eq(top[1].anchor, "muyata/tier")
  assert_eq(top[1].total_weight, 6)
}

///|
test "scout observe fails when not active" {
  let cave = @cave.CaveStore::standard()
  let mulsp = @mulsp.MulspState::new("s-1", "claude", "wasm-gc", "emergent")
  let mulsp2 = mulsp.attach("claude", "/").unwrap()
  let mulsp3 = mulsp2.activate().unwrap()
  let muyata = @muyata.MuyataProfile::claude(
    @muyata.Sonnet,
    @muyata.Delegation,
    "wasm-gc",
    "emergent",
  )
  let orch = @claude.ClaudeOrchestrator::new(mulsp3, muyata, cave).unwrap()
  let scout = orch.spawn_haiku(@muyata.Observation).unwrap()
  // Quiesce the scout
  assert_true(scout.quiesce())
  assert_eq(scout.is_active(), false)
  // Observe should fail
  assert_eq(scout.observe("anything", 5, 1000), false)
}

// ---------------------------------------------------------------------------
// Scout quiescence
// ---------------------------------------------------------------------------

///|
test "scout quiesces cleanly" {
  let cave = @cave.CaveStore::standard()
  let mulsp = @mulsp.MulspState::new("s-1", "claude", "wasm-gc", "emergent")
  let mulsp2 = mulsp.attach("claude", "/").unwrap()
  let mulsp3 = mulsp2.activate().unwrap()
  let muyata = @muyata.MuyataProfile::claude(
    @muyata.Sonnet,
    @muyata.Delegation,
    "wasm-gc",
    "emergent",
  )
  let orch = @claude.ClaudeOrchestrator::new(mulsp3, muyata, cave).unwrap()
  let scout = orch.spawn_haiku(@muyata.Observation).unwrap()
  let _ = scout.observe("node/kernel", 5, 500)
  assert_true(scout.is_active())
  assert_true(scout.quiesce())
  assert_eq(scout.is_active(), false)
  // Loci retains the quiesced state snapshot
  let snap = cave.loci_get("m:" + scout.scout_id())
  assert_true(snap is Some(_))
}

///|
test "deposit count tracks observations" {
  let cave = @cave.CaveStore::standard()
  let mulsp = @mulsp.MulspState::new("s-1", "claude", "wasm-gc", "emergent")
  let mulsp2 = mulsp.attach("claude", "/").unwrap()
  let mulsp3 = mulsp2.activate().unwrap()
  let muyata = @muyata.MuyataProfile::claude(
    @muyata.Sonnet,
    @muyata.Delegation,
    "wasm-gc",
    "emergent",
  )
  let orch = @claude.ClaudeOrchestrator::new(mulsp3, muyata, cave).unwrap()
  let scout = orch.spawn_haiku(@muyata.Observation).unwrap()
  assert_eq(scout.deposit_count(), 0)
  let _ = scout.observe("a", 1, 0)
  let _ = scout.observe("b", 2, 0)
  let _ = scout.observe("a", 3, 0)
  assert_eq(scout.deposit_count(), 3)
}

// ---------------------------------------------------------------------------
// Loci persistence — stigmergy survives independently of in-memory state
// ---------------------------------------------------------------------------

///|
test "loci cave retains stigma after scout quiesces" {
  let cave = @cave.CaveStore::standard()
  let mulsp = @mulsp.MulspState::new("s-1", "claude", "wasm-gc", "emergent")
  let mulsp2 = mulsp.attach("claude", "/").unwrap()
  let mulsp3 = mulsp2.activate().unwrap()
  let muyata = @muyata.MuyataProfile::claude(
    @muyata.Sonnet,
    @muyata.Delegation,
    "wasm-gc",
    "emergent",
  )
  let orch = @claude.ClaudeOrchestrator::new(mulsp3, muyata, cave).unwrap()
  let scout = orch.spawn_haiku(@muyata.Observation).unwrap()
  let _ = scout.observe("spore/mobile-agent", 12, 1000)
  let _ = scout.observe("spore/mobile-agent", 8, 2000)
  let _ = scout.quiesce()
  // The orchestrator can still read the stigma from loci
  let entry = orch.read_anchor("spore/mobile-agent")
  assert_true(entry is Some(_))
  let e = entry.unwrap()
  assert_eq(e.total_weight, 20)
  assert_eq(e.contributor_count, 2)
}
