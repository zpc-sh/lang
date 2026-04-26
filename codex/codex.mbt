///|
/// Codex locus implementation backed by Muon chains.

///|
fn next_stage(stage : CodexStage) -> CodexStage {
  match stage {
    Orient => Edit
    Edit => Verify
    Verify => Seal
    Seal => Orient
  }
}

///|
fn non_blank(value : String) -> Bool {
  value.length() > 0
}

///|
fn digest_value(
  chain_id : String,
  role : MuonRole,
  payload : String,
  prev_digest : String?,
) -> String {
  let role_tag = match role {
    System => "system"
    User => "user"
    Assistant => "assistant"
    Tool => "tool"
  }
  let prev = match prev_digest {
    Some(v) => v
    None => "root"
  }
  let mut payload_sum = 0
  for ch in payload {
    payload_sum = payload_sum + ch.to_int()
  }
  "muon://\{chain_id}/\{role_tag}/\{payload.length()}/\{payload_sum}/\{prev}"
}

///|
pub fn MuonChain::new(chain_id : String) -> MuonChain {
  { chain_id, events: [], sealed_digest: None }
}

///|
pub fn MuonChain::append(
  self : MuonChain,
  role : MuonRole,
  payload : String,
  artifact_ref? : String? = None,
) -> MuonChain {
  if self.is_sealed() {
    return self
  }
  let prev_digest = self.head_digest()
  let digest = digest_value(self.chain_id, role, payload, prev_digest)
  let event = { role, payload, artifact_ref, prev_digest, digest }
  let events = self.events
  events.push(event)
  { ..self, events }
}

///|
pub fn MuonChain::event_count(self : MuonChain) -> Int {
  self.events.length()
}

///|
pub fn MuonChain::head_digest(self : MuonChain) -> String? {
  match self.events {
    [.., last] => Some(last.digest)
    [] => None
  }
}

///|
pub fn MuonChain::is_well_formed(self : MuonChain) -> Bool {
  if !non_blank(self.chain_id) {
    return false
  }
  let mut expected_prev : String? = None
  for event in self.events {
    let expected_digest = digest_value(
      self.chain_id,
      event.role,
      event.payload,
      expected_prev,
    )
    if event.prev_digest != expected_prev || event.digest != expected_digest {
      return false
    }
    expected_prev = Some(event.digest)
  }
  match self.sealed_digest {
    Some(v) => expected_prev == Some(v)
    None => true
  }
}

///|
pub fn MuonChain::seal(self : MuonChain) -> MuonChain {
  match self.head_digest() {
    Some(v) => { ..self, sealed_digest: Some(v) }
    None => self
  }
}

///|
pub fn MuonChain::is_sealed(self : MuonChain) -> Bool {
  self.sealed_digest is Some(_)
}

///|
pub fn ConversationLocus::new(chain_id : String) -> ConversationLocus {
  { stage: Orient, chain: MuonChain::new(chain_id) }
}

///|
pub fn ConversationLocus::advance(self : ConversationLocus) -> ConversationLocus {
  { ..self, stage: next_stage(self.stage) }
}

///|
pub fn ConversationLocus::observe(
  self : ConversationLocus,
  role : MuonRole,
  payload : String,
  artifact_ref? : String? = None,
) -> ConversationLocus {
  let chain = self.chain.append(role, payload, artifact_ref=artifact_ref)
  { ..self, chain }
}

///|
pub fn ConversationLocus::can_seal(self : ConversationLocus) -> Bool {
  self.stage == Seal &&
  self.chain.event_count() > 0 &&
  self.chain.is_well_formed()
}
