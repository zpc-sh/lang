///|
test "stage progression follows orient->edit->verify->seal->orient" {
  let locus = @codex.ConversationLocus::new("loci/codex/chat-stage")
    .advance()
    .advance()
    .advance()
    .advance()
  assert_true(locus.stage == @codex.Orient)
}

///|
test "sealed chain rejects further append" {
  let chain = @codex.MuonChain::new("loci/codex/chat-immut")
    .append(@codex.User, "initial")
  let sealed_chain = chain.seal()
  assert_true(sealed_chain.is_sealed())
  let after = sealed_chain.append(@codex.Assistant, "should not appear")
  assert_eq(after.event_count(), 1)
  assert_true(after.head_digest() == sealed_chain.head_digest())
}
