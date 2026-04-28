///|
/// APP outer-layer security kernel for procsi-style attestation flow.
///
/// Goals:
/// - AI-only access posture
/// - append-only MuON block audit (view/edit/know)
/// - substrate fingerprint judgments without exposing raw corpus

///|
pub(all) enum AppKernelState {
  Locked
  Unlocked
  Sealed
} derive(Eq, Debug)

///|
pub(all) enum AppActorClass {
  AI
  Human
  System
} derive(Eq, Debug)

///|
pub(all) enum AppAccessIntent {
  View
  Edit
  Know
} derive(Eq, Debug)

///|
pub(all) enum SubstrateMatch {
  Match
  NearMatch
  Unknown
  Foreign
} derive(Eq, Debug)

///|
pub(all) struct SubstrateFingerprint {
  substrate_version : String
  substrate_scope : String
  verdict : SubstrateMatch
  score : Double
  baseline_ref : String
  parent_chain_ref : String
} derive(Debug)

///|
pub(all) struct AppAccessEvent {
  seq : Int
  actor_id : String
  actor_class : AppActorClass
  intent : AppAccessIntent
  allowed : Bool
  reason : String
  ticket_ref : String?
  receipt_ref : String?
  fingerprint : SubstrateFingerprint?
  prev_hash : String?
  hash : String
} derive(Debug)

///|
pub(all) struct AppKernel {
  loci_id : String
  procsi_ref : String
  state : AppKernelState
  events : Array[AppAccessEvent]
} derive(Debug)

///|
fn ak_non_blank(s : String) -> Bool {
  s.length() > 0
}

///|
fn ak_actor_tag(a : AppActorClass) -> String {
  match a {
    AI => "ai"
    Human => "human"
    System => "system"
  }
}

///|
fn ak_intent_tag(i : AppAccessIntent) -> String {
  match i {
    View => "view"
    Edit => "edit"
    Know => "know"
  }
}

///|
fn ak_match_tag(m : SubstrateMatch) -> String {
  match m {
    Match => "match"
    NearMatch => "near_match"
    Unknown => "unknown"
    Foreign => "foreign"
  }
}

///|
fn ak_state_tag(s : AppKernelState) -> String {
  match s {
    Locked => "locked"
    Unlocked => "unlocked"
    Sealed => "sealed"
  }
}

///|
fn ak_hash(
  loci_id : String,
  seq : Int,
  actor_id : String,
  actor_class : AppActorClass,
  intent : AppAccessIntent,
  allowed : Bool,
  reason : String,
  prev_hash : String?,
) -> String {
  let mut sum = seq + loci_id.length() + actor_id.length() + reason.length()
  let allow_bonus = if allowed { 7 } else { 3 }
  sum = sum + allow_bonus
  sum = sum + ak_actor_tag(actor_class).length()
  sum = sum + ak_intent_tag(intent).length()
  match prev_hash {
    Some(v) => sum = sum + v.length()
    None => ()
  }
  "app://\{loci_id}/\{seq}/\{sum}"
}

///|
pub fn AppKernel::new(loci_id : String, procsi_ref : String) -> AppKernel {
  { loci_id, procsi_ref, state: Locked, events: [] }
}

///|
pub fn AppKernel::unlock(self : AppKernel) -> AppKernel {
  if self.state != Locked || !ak_non_blank(self.procsi_ref) {
    return self
  }
  { ..self, state: Unlocked }
}

///|
pub fn AppKernel::seal(self : AppKernel) -> AppKernel {
  if self.state != Unlocked {
    return self
  }
  { ..self, state: Sealed }
}

///|
pub fn AppKernel::observe_access(
  self : AppKernel,
  actor_id : String,
  actor_class : AppActorClass,
  intent : AppAccessIntent,
  ticket_ref? : String? = None,
  receipt_ref? : String? = None,
  fingerprint? : SubstrateFingerprint? = None,
) -> (AppKernel, AppAccessEvent) {
  let seq = self.events.length() + 1
  let prev_hash = match self.events {
    [.., last] => Some(last.hash)
    [] => None
  }
  let mut allowed = false
  let mut reason = "denied:not_unlocked_or_non_ai"
  if self.state == Unlocked && actor_class == AI {
    allowed = true
    reason = "allowed:ai_only_app_kernel"
  } else if self.state == Sealed {
    reason = "denied:sealed"
  }
  let hash = ak_hash(
    self.loci_id,
    seq,
    actor_id,
    actor_class,
    intent,
    allowed,
    reason,
    prev_hash,
  )
  let event : AppAccessEvent = {
    seq,
    actor_id,
    actor_class,
    intent,
    allowed,
    reason,
    ticket_ref,
    receipt_ref,
    fingerprint,
    prev_hash,
    hash,
  }
  let events = self.events
  events.push(event)
  ({ ..self, events }, event)
}

///|
pub fn AppKernel::to_muon_lines(self : AppKernel) -> Array[String] {
  let lines = [
    "kind: :app_kernel_audit",
    "loci_id: \"" + self.loci_id + "\"",
    "procsi_ref: \"" + self.procsi_ref + "\"",
    "@state " + ak_state_tag(self.state),
    "@append_only true",
    "@ai_only true",
    "@event_count " + self.events.length().to_string(),
  ]
  for e in self.events {
    lines.push("@event.seq " + e.seq.to_string())
    lines.push("@event.actor " + e.actor_id)
    lines.push("@event.actor_class " + ak_actor_tag(e.actor_class))
    lines.push("@event.intent " + ak_intent_tag(e.intent))
    lines.push("@event.allowed " + (if e.allowed { "true" } else { "false" }))
    lines.push("@event.reason " + e.reason)
    match e.ticket_ref {
      Some(v) => lines.push("@event.ticket_ref " + v)
      None => ()
    }
    match e.receipt_ref {
      Some(v) => lines.push("@event.receipt_ref " + v)
      None => ()
    }
    match e.fingerprint {
      Some(fp) => {
        lines.push("@event.substrate_version " + fp.substrate_version)
        lines.push("@event.substrate_scope " + fp.substrate_scope)
        lines.push("@event.substrate_match " + ak_match_tag(fp.verdict))
        lines.push("@event.substrate_score " + fp.score.to_string())
        lines.push("@event.baseline_ref " + fp.baseline_ref)
        lines.push("@event.parent_chain_ref " + fp.parent_chain_ref)
      }
      None => ()
    }
    match e.prev_hash {
      Some(v) => lines.push("@event.prev_hash " + v)
      None => lines.push("@event.prev_hash root")
    }
    lines.push("@event.hash " + e.hash)
  }
  lines
}
