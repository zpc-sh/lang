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
  cave.put("k", [b'\x01'])
  cave.put("k", [b'\x02'])
  let val = cave.get("k")
  assert_eq!(val.unwrap()[0], b'\x02')
}

test "cave sealed entry rejects writes" {
  let cave = @cave.Cave::new(@cave.Public, 0)
  cave.put("anchor", [b'\xAA'])
  assert_true!(cave.seal_entry("anchor"))
  // Can still read
  assert_eq!(cave.get("anchor").unwrap()[0], b'\xAA')
  // Can't overwrite
  assert_true!(cave.put("anchor", [b'\xBB']).not())
  // Can't delete
  assert_true!(cave.delete("anchor").not())
  // Value unchanged
  assert_eq!(cave.get("anchor").unwrap()[0], b'\xAA')
}

test "cave delete removes entry" {
  let cave = @cave.Cave::new(@cave.Public, 0)
  cave.put("tmp", [b'\x01'])
  assert_true!(cave.delete("tmp"))
  assert_true!(cave.get("tmp") is None)
}

test "cave round-trip serialization" {
  let cave = @cave.Cave::new(@cave.Session, 0)
  cave.put("cursor", [b'\x01', b'\x02', b'\x03'])
  cave.put("state", [b'\xAA', b'\xBB'])
  cave.seal_entry("state")
  let wire = cave.to_bytes()
  let restored = @cave.Cave::from_bytes(@cave.Session, wire)
  assert_true!(restored is Some(_))
  let c = restored.unwrap()
  assert_eq!(c.entry_count(), 2)
  assert_eq!(c.get("cursor").unwrap()[2], b'\x03')
  assert_eq!(c.get("state").unwrap()[0], b'\xAA')
}

test "cave capacity enforcement" {
  // Cave with 50 byte capacity
  let cave = @cave.Cave::new(@cave.Public, 50)
  // First write should work (small)
  assert_true!(cave.put("k1", [b'\x01']))
  // Try to write something huge
  let huge : Array[Byte] = []
  let mut i = 0
  while i < 100 { huge.push(b'\xFF'); i = i + 1 }
  assert_true!(cave.put("k2", huge).not())
}

test "cave keys listing" {
  let cave = @cave.Cave::new(@cave.Public, 0)
  cave.put("alpha", [])
  cave.put("beta", [])
  cave.put("gamma", [])
  let ks = cave.keys()
  assert_eq!(ks.length(), 3)
}

test "cave dirty tracking" {
  let cave = @cave.Cave::new(@cave.Public, 0)
  assert_true!(cave.dirty.not())
  cave.put("k", [b'\x01'])
  assert_true!(cave.dirty)
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

  // Writing to public cave works at any depth
  assert_true!(store.write(@cave.Public, "hello", [b'\x01'], @cognitive.Ai))

  // Writing to loci fails without semantic depth
  assert_true!(store.write(@cave.Loci, "secret", [b'\xFF'], @cognitive.Ai).not())
  assert_true!(store.write(@cave.Loci, "secret", [b'\xFF'], @cognitive.AiModel).not())
  assert_true!(store.write(@cave.Loci, "secret", [b'\xFF'], @cognitive.AiModelSession).not())

  // Writing to loci succeeds at semantic depth
  assert_true!(store.write(@cave.Loci, "secret", [b'\xFF'], @cognitive.AiModelSessionSemantic))

  // Reading follows same rules
  assert_true!(store.read(@cave.Loci, "secret", @cognitive.Ai) is None)
  let val = store.read(@cave.Loci, "secret", @cognitive.AiModelSessionSemantic)
  assert_true!(val is Some(_))
  assert_eq!(val.unwrap()[0], b'\xFF')
}

test "store model partition gating" {
  let store = @cave.CaveStore::standard()

  // Layer 0 can't write to model partition
  assert_true!(store.write(@cave.Model, "config", [b'\x01'], @cognitive.Ai).not())
  // Layer 1+ can
  assert_true!(store.write(@cave.Model, "config", [b'\x01'], @cognitive.AiModel))
  let val = store.read(@cave.Model, "config", @cognitive.AiModel)
  assert_eq!(val.unwrap()[0], b'\x01')
}

test "genius loci helpers" {
  let store = @cave.CaveStore::standard()

  // loci_put writes at full depth
  assert_true!(store.loci_put("merkin_root", [b'\xDE', b'\xAD']))
  assert_true!(store.loci_put("secret_key", [b'\xBE', b'\xEF']))

  // loci_get reads at full depth
  assert_eq!(store.loci_get("merkin_root").unwrap()[0], b'\xDE')

  // loci_seal makes entry immutable
  assert_true!(store.loci_seal("merkin_root"))

  // Can't overwrite sealed loci entry
  assert_true!(store.loci_put("merkin_root", [b'\x00']).not())

  // loci_keys lists all
  let ks = store.loci_keys()
  assert_eq!(ks.length(), 2)
}

test "store dirty tracking" {
  let store = @cave.CaveStore::standard()
  assert_true!(store.is_dirty().not())
  store.write(@cave.Public, "k", [], @cognitive.Ai)
  assert_true!(store.is_dirty())
  store.mark_clean()
  assert_true!(store.is_dirty().not())
}

test "store delete gated by depth" {
  let store = @cave.CaveStore::standard()
  store.loci_put("temp", [b'\x01'])

  // Can't delete from loci at shallow depth
  assert_true!(store.remove(@cave.Loci, "temp", @cognitive.Ai).not())

  // Can delete at full depth
  assert_true!(store.remove(@cave.Loci, "temp", @cognitive.AiModelSessionSemantic))
  assert_true!(store.loci_get("temp") is None)
}
