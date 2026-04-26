///|
test "conversation starts in orient with empty muon chain" {
  let locus = @codex.ConversationLocus::new("loci/codex/chat-001")
  assert_true(locus.stage == @codex.Orient)
  assert_eq(locus.chain.event_count(), 0)
  assert_true(locus.chain.head_digest() is None)
}

///|
test "append creates deterministic head digest and preserves well-formedness" {
  let chain = @codex.MuonChain::new("loci/codex/chat-001")
    .append(@codex.User, "hi codex")
    .append(@codex.Assistant, "working on it")
  assert_eq(chain.event_count(), 2)
  assert_true(chain.head_digest() is Some(_))
  assert_true(chain.is_well_formed())
}
