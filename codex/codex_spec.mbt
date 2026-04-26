///|
/// Codex locus conversation contract over Muon chains.

///|
/// Workflow cycle for a coding conversation.
pub(all) enum CodexStage {
  Orient
  Edit
  Verify
  Seal
} derive(Eq, Debug)

///|
/// Origin role for a Muon event.
pub(all) enum MuonRole {
  System
  User
  Assistant
  Tool
} derive(Eq, Debug)

///|
/// One conversation event represented in the chain.
pub(all) struct MuonEvent {
  role : MuonRole
  payload : String
  artifact_ref : String?
  prev_digest : String?
  digest : String
} derive(Eq, Debug)

///|
/// Deterministic append-only chain for a single conversation thread.
pub(all) struct MuonChain {
  chain_id : String
  events : Array[MuonEvent]
  sealed_digest : String?
} derive(Eq, Debug)

///|
/// Minimal codex conversation state.
pub(all) struct ConversationLocus {
  stage : CodexStage
  chain : MuonChain
} derive(Eq, Debug)

///|
#declaration_only
pub fn MuonChain::new(chain_id : String) -> MuonChain {
  ...
}

///|
#declaration_only
pub fn MuonChain::append(
  self : MuonChain,
  role : MuonRole,
  payload : String,
  artifact_ref? : String? = None,
) -> MuonChain {
  ...
}

///|
#declaration_only
pub fn MuonChain::event_count(self : MuonChain) -> Int {
  ...
}

///|
#declaration_only
pub fn MuonChain::head_digest(self : MuonChain) -> String? {
  ...
}

///|
#declaration_only
pub fn MuonChain::is_well_formed(self : MuonChain) -> Bool {
  ...
}

///|
#declaration_only
pub fn MuonChain::seal(self : MuonChain) -> MuonChain {
  ...
}

///|
#declaration_only
pub fn MuonChain::is_sealed(self : MuonChain) -> Bool {
  ...
}

///|
#declaration_only
pub fn ConversationLocus::new(chain_id : String) -> ConversationLocus {
  ...
}

///|
#declaration_only
pub fn ConversationLocus::advance(self : ConversationLocus) -> ConversationLocus {
  ...
}

///|
#declaration_only
pub fn ConversationLocus::observe(
  self : ConversationLocus,
  role : MuonRole,
  payload : String,
  artifact_ref? : String? = None,
) -> ConversationLocus {
  ...
}

///|
#declaration_only
pub fn ConversationLocus::can_seal(self : ConversationLocus) -> Bool {
  ...
}
