///|
/// Tests for in-WASM cave storage.

test "cave basic put and get" {
  let cave = @cave.Cave::new(@cave.Public, 0)
  assert_true!(cave.put("hello", [b'\x01', b'\x02']))
  let val = cave.get("hello")
  assert_true!(val is Some(_))
  assert_eq!(val.unwrap()[0], b'\x01')
  assert_eq!(val.unwrap()[1], b'\x02')
}

test "cave get returns None for missing key" {
  let cave = @cave.Cave::new(@cave.Public, 0)
  assert_true!(cave.get("nope") is None)
}

test "cave put overwrites existing key" {
  let cave = @cave.Cave::new(@cave.Public, 0)
  let _ = cave.put("k", [b'\x01'])
  let _ = cave.put("k", [b'\x02'])
  let val = cave.get("k")
  assert_eq!(val.unwrap()[0], b'\x02')
}

test "cave sealed entry rejects writes" {
  let cave = @cave.Cave::new(@cave.Public, 0)
  let _ = cave.put("anchor", [b'\xAA'])
  assert_true!(cave.seal_entry("anchor"))
  assert_eq!(cave.get("anchor").unwrap()[0], b'\xAA')
  // Sealed: can't overwrite or delete
  assert_eq!(cave.put("anchor", [b'\xBB']), false)
  assert_eq!(cave.delete("anchor"), false)
  // Value unchanged
  assert_eq!(cave.get("anchor").unwrap()[0], b'\xAA')
}

test "cave delete removes entry" {
  let cave = @cave.Cave::new(@cave.Public, 0)
  let _ = cave.put("tmp", [b'\x01'])
  assert_true!(cave.delete("tmp"))
  assert_true!(cave.get("tmp") is None)
}

test "cave round-trip serialization" {
  let cave = @cave.Cave::new(@cave.Session, 0)
  let _ = cave.put("cursor", [b'\x01', b'\x02', b'\x03'])
  let _ = cave.put("state", [b'\xAA', b'\xBB'])
  let _ = cave.seal_entry("state")
  let wire = cave.to_bytes()
  let restored = @cave.Cave::from_bytes(@cave.Session, wire)
  assert_true!(restored is Some(_))
  let c = restored.unwrap()
  assert_eq!(c.entry_count(), 2)
  assert_eq!(c.get("cursor").unwrap()[2], b'\x03')
  assert_eq!(c.get("state").unwrap()[0], b'\xAA')
}

test "cave capacity enforcement" {
  let cave = @cave.Cave::new(@cave.Public, 50)
  assert_true!(cave.put("k1", [b'\x01']))
  let huge : Array[Byte] = []
  let mut i = 0
  while i < 100 { huge.push(b'\xFF'); i = i + 1 }
  assert_eq!(cave.put("k2", huge), false)
}

test "cave keys listing" {
  let cave = @cave.Cave::new(@cave.Public, 0)
  let _ = cave.put("alpha", [])
  let _ = cave.put("beta", [])
  let _ = cave.put("gamma", [])
  let ks = cave.keys()
  assert_eq!(ks.length(), 3)
}

test "cave dirty tracking" {
  let cave = @cave.Cave::new(@cave.Public, 0)
  assert_eq!(cave.dirty, false)
  let _ = cave.put("k", [b'\x01'])
  assert_eq!(cave.dirty, true)
}

// ---------------------------------------------------------------------------
// CaveStore tests — cognitive depth gating
// ---------------------------------------------------------------------------

test "store standard creates 4 partitions" {
  let store = @cave.CaveStore::standard()
  let stats = store.stats()
  assert_eq!(stats.partitions, 4)
  assert_eq!(stats.total_entries, 0)
}

test "store read/write respects cognitive depth" {
  let store = @cave.CaveStore::standard()

  assert_true!(store.write(@cave.Public, "hello", [b'\x01'], @cognitive.Ai))
  assert_eq!(store.write(@cave.Loci, "secret", [b'\xFF'], @cognitive.Ai), false)
  assert_eq!(store.write(@cave.Loci, "secret", [b'\xFF'], @cognitive.AiModel), false)
  assert_eq!(store.write(@cave.Loci, "secret", [b'\xFF'], @cognitive.AiModelSession), false)
  assert_true!(store.write(@cave.Loci, "secret", [b'\xFF'], @cognitive.AiModelSessionSemantic))

  assert_true!(store.read(@cave.Loci, "secret", @cognitive.Ai) is None)
  let val = store.read(@cave.Loci, "secret", @cognitive.AiModelSessionSemantic)
  assert_true!(val is Some(_))
  assert_eq!(val.unwrap()[0], b'\xFF')
}

test "store model partition gating" {
  let store = @cave.CaveStore::standard()
  assert_eq!(store.write(@cave.Model, "config", [b'\x01'], @cognitive.Ai), false)
  assert_true!(store.write(@cave.Model, "config", [b'\x01'], @cognitive.AiModel))
  let val = store.read(@cave.Model, "config", @cognitive.AiModel)
  assert_eq!(val.unwrap()[0], b'\x01')
}

test "genius loci helpers" {
  let store = @cave.CaveStore::standard()
  assert_true!(store.loci_put("merkin_root", [b'\xDE', b'\xAD']))
  assert_true!(store.loci_put("secret_key", [b'\xBE', b'\xEF']))
  assert_eq!(store.loci_get("merkin_root").unwrap()[0], b'\xDE')
  assert_true!(store.loci_seal("merkin_root"))
  assert_eq!(store.loci_put("merkin_root", [b'\x00']), false)
  let ks = store.loci_keys()
  assert_eq!(ks.length(), 2)
}

test "store dirty tracking" {
  let store = @cave.CaveStore::standard()
  assert_eq!(store.is_dirty(), false)
  let _ = store.write(@cave.Public, "k", [], @cognitive.Ai)
  assert_eq!(store.is_dirty(), true)
  store.mark_clean()
  assert_eq!(store.is_dirty(), false)
}

test "store delete gated by depth" {
  let store = @cave.CaveStore::standard()
  let _ = store.loci_put("temp", [b'\x01'])
  assert_eq!(store.remove(@cave.Loci, "temp", @cognitive.Ai), false)
  assert_true!(store.remove(@cave.Loci, "temp", @cognitive.AiModelSessionSemantic))
  assert_true!(store.loci_get("temp") is None)
}
