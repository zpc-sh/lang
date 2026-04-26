///|
test "from_bytes rejects truncated cave payload" {
  let truncated : Array[Byte] = [b'\x01', b'\x00', b'\x00', b'\x00']
  assert_true(@cave.Cave::from_bytes(@cave.Public, truncated) is None)
}

///|
test "from_bytes rejects bad entry payload after valid header" {
  let bad : Array[Byte] = []
  // Header: count=1 epoch=0 capacity=0
  bad.push(b'\x01')
  bad.push(b'\x00')
  bad.push(b'\x00')
  bad.push(b'\x00')
  for _ in 0..<8 {
    bad.push(b'\x00')
  }
  // Broken entry magic.
  bad.push(b'\x99')
  bad.push(b'\x88')

  assert_true(@cave.Cave::from_bytes(@cave.Public, bad) is Some(_))
  let cave = @cave.Cave::from_bytes(@cave.Public, bad).unwrap()
  // Malformed entry is ignored; no decoded entries.
  assert_eq(cave.entry_count(), 0)
}
