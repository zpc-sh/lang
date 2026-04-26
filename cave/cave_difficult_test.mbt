///|
test "loci operations remain gated and mark_clean resets global dirty state" {
  let store = @cave.CaveStore::standard()

  assert_eq(store.write(@cave.Loci, "secret", [b'\x10'], @cognitive.Ai), false)
  assert_true(
    store.write(
      @cave.Loci,
      "secret",
      [b'\x10'],
      @cognitive.AiModelSessionSemantic,
    ),
  )
  assert_true(store.is_dirty())

  assert_true(store.read(@cave.Loci, "secret", @cognitive.Ai) is None)
  let secret = store.read(
    @cave.Loci,
    "secret",
    @cognitive.AiModelSessionSemantic,
  )
  assert_true(secret is Some(_))
  assert_eq(secret.unwrap()[0], b'\x10')

  store.mark_clean()
  assert_eq(store.is_dirty(), false)
}

///|
test "sealing an entry keeps it immutable across store helpers" {
  let store = @cave.CaveStore::standard()
  assert_true(store.loci_put("anchor", [b'\xAA']))
  assert_true(store.loci_seal("anchor"))
  assert_eq(store.loci_put("anchor", [b'\xBB']), false)
  assert_eq(store.loci_get("anchor").unwrap()[0], b'\xAA')
}
