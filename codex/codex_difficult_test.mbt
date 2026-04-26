///|
test "can_seal only when stage is seal and chain is valid" {
  let not_ready = @codex.ConversationLocus::new("loci/codex/chat-seal")
    .observe(@codex.User, "draft request")
    .observe(@codex.Assistant, "draft response")
  assert_true(!not_ready.can_seal())

  let ready = not_ready.advance().advance().advance()
  assert_true(ready.stage == @codex.Seal)
  assert_true(ready.can_seal())
}

///|
test "tampered chain fails well-formed validation" {
  let chain = @codex.MuonChain::new("loci/codex/chat-tamper")
    .append(@codex.User, "line-1")
    .append(@codex.Assistant, "line-2")
  assert_true(chain.is_well_formed())

  let events = chain.events
  let first = events[0]
  events[0] = { ..first, payload: "line-1-tampered" }
  let tampered = { ..chain, events }
  assert_true(!tampered.is_well_formed())
}
