///|
test "partition section names and default depth contract" {
  assert_eq(@cave.Public.section_name(), ".cave.public")
  assert_eq(@cave.Model.section_name(), ".cave.model")
  assert_eq(@cave.Session.section_name(), ".cave.session")
  assert_eq(@cave.Loci.section_name(), ".cave.loci")
  assert_eq(@cave.Custom("chatgpt").section_name(), ".cave.chatgpt")

  assert_eq(@cave.Public.required_depth(), @cognitive.Ai)
  assert_eq(@cave.Custom("x").required_depth(), @cognitive.AiModel)
}

///|
test "standard store exposes expected partition count" {
  let store = @cave.CaveStore::standard()
  assert_eq(store.stats().partitions, 4)
}
