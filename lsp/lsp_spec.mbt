///|
/// LSP dual contract surface.
///
/// Every public LSP function is declared as a dual block:
///   - mulsp side: composition/emission posture
///   - muyata side: ingestion/normalization posture
///
/// `wrap_mulsp` gives the composition block for a function.
/// `wrap_muyata` returns the inverted ingestion block.

///|
pub(all) enum LspCategory {
  Framing
  Message
  ClientOps
  ClientRuntime
  Scanner
} derive(Eq, Debug)

///|
impl Show for LspCategory with output(self, logger) {
  logger.write_string(
    match self {
      Framing => "Framing"
      Message => "Message"
      ClientOps => "ClientOps"
      ClientRuntime => "ClientRuntime"
      Scanner => "Scanner"
    },
  )
}

///|
pub(all) enum LspFuncType {
  Constructor
  Codec
  Parser
  Router
  Observer
  Utility
} derive(Eq, Debug)

///|
impl Show for LspFuncType with output(self, logger) {
  logger.write_string(
    match self {
      Constructor => "Constructor"
      Codec => "Codec"
      Parser => "Parser"
      Router => "Router"
      Observer => "Observer"
      Utility => "Utility"
    },
  )
}

///|
pub(all) enum DualRole {
  Mulsp
  Muyata
} derive(Eq, Debug)

///|
impl Show for DualRole with output(self, logger) {
  logger.write_string(
    match self {
      Mulsp => "mulsp"
      Muyata => "muyata"
    },
  )
}

///|
pub(all) struct LspFnDualSpec {
  name : String
  inverse_name : String
  category : LspCategory
  func_type : LspFuncType
  can_fail : Bool
  mulsp_protocol : String
  muyata_protocol : String
  mulsp_seed : Int
  muyata_seed : Int
} derive(Debug)

///|
pub(all) struct LspContractBlock {
  function_name : String
  inverse_function : String
  role : DualRole
  protocol : String
  inverse_protocol : String
  seed : Int
  inverse_seed : Int
  can_fail : Bool
} derive(Debug)

///|
pub(all) enum LspProofStatus {
  Open
  Covered
  Proved
  Reviewed
  Waived
  Blocked
  Failed
} derive(Eq, Debug)

///|
pub(all) struct LspProofObligation {
  obligation_id : String
  required : Bool
  status : LspProofStatus
} derive(Eq, Debug)

///|
pub fn LspProofObligation::is_discharged(self : LspProofObligation) -> Bool {
  match self.status {
    Covered | Proved | Reviewed | Waived => true
    Open | Blocked | Failed => false
  }
}

///|
pub(all) enum LspComposabilityStatus {
  NotComposable
  PartiallyComposable
  FullyComposable
} derive(Eq, Debug)

///|
pub(all) enum LspDeployQueueStatus {
  NotQueued
  Queued
  Deployable
  Blocked
} derive(Eq, Debug)

///|
pub(all) struct LspEmissionSurface {
  docs_ref : String?
  gallery_ref : String?
  wasm_plugin_ref : String?
  deploy_queue_ref : String?
  composability : LspComposabilityStatus
  deploy_status : LspDeployQueueStatus
} derive(Debug)

///|
pub(all) struct LspDualContractBinding {
  contract_id : String
  function_name : String
  inverse_function : String
  test_result_ref : String?
  coverage_ref : String?
  proof_ref : String?
  dialogue_ref : String?
  side_effect_observed : Bool
  obligations : Array[LspProofObligation]
  emission : LspEmissionSurface
} derive(Debug)

///|
fn non_blank(s : String) -> Bool {
  s.length() > 0
}

///|
fn has_ref(s : String?) -> Bool {
  match s {
    Some(v) => non_blank(v)
    None => false
  }
}

///|
fn all_required_obligations_discharged(
  obligations : Array[LspProofObligation],
) -> Bool {
  for obligation in obligations {
    if obligation.required && !obligation.is_discharged() {
      return false
    }
  }
  true
}

///|
pub fn LspDualContractBinding::can_seal(
  self : LspDualContractBinding,
) -> Bool where {
  proof_ensure: result => !result || has_ref(self.test_result_ref),
  proof_ensure: result => !result || has_ref(self.coverage_ref),
  proof_ensure: result => !result || has_ref(self.proof_ref),
  proof_ensure: result => !result || all_required_obligations_discharged(self.obligations),
} {
  if !non_blank(self.contract_id) {
    return false
  }
  if !non_blank(self.function_name) || !non_blank(self.inverse_function) {
    return false
  }
  if !has_ref(self.test_result_ref) || !has_ref(self.coverage_ref) || !has_ref(self.proof_ref) {
    return false
  }
  if !self.side_effect_observed {
    return false
  }
  all_required_obligations_discharged(self.obligations)
}

///|
pub fn LspDualContractBinding::is_deploy_queue_ready(
  self : LspDualContractBinding,
) -> Bool where {
  proof_ensure: result => !result || self.can_seal(),
} {
  if !self.can_seal() {
    return false
  }
  if !has_ref(self.emission.wasm_plugin_ref) || !has_ref(self.emission.deploy_queue_ref) {
    return false
  }
  if self.emission.composability != FullyComposable {
    return false
  }
  self.emission.deploy_status == Queued || self.emission.deploy_status == Deployable
}

///|
pub fn LspDualContractBinding::is_cross_repo_ready(
  self : LspDualContractBinding,
) -> Bool where {
  proof_ensure: result => !result || self.is_deploy_queue_ready(),
} {
  self.is_deploy_queue_ready() && has_ref(self.dialogue_ref)
}

///|
pub fn LspDualContractBinding::to_muon_lines(
  self : LspDualContractBinding,
) -> Array[String] {
  let lines = [
    "kind: :lsp_dual_contract_binding_spec",
    "binding_model: \"contract -> tests -> coverage -> proof obligations -> seal posture\"",
    "contract_id: \"" + self.contract_id + "\"",
    "@function " + self.function_name,
    "@inverse " + self.inverse_function,
    "@seal_ready " + (if self.can_seal() { "true" } else { "false" }),
    "@deploy_ready " + (if self.is_deploy_queue_ready() { "true" } else { "false" }),
    "@cross_repo_ready " + (if self.is_cross_repo_ready() { "true" } else { "false" }),
  ]
  match self.test_result_ref {
    Some(v) => lines.push("test_result_ref: \"" + v + "\"")
    None => ()
  }
  match self.coverage_ref {
    Some(v) => lines.push("coverage_ref: \"" + v + "\"")
    None => ()
  }
  match self.proof_ref {
    Some(v) => lines.push("proof_ref: \"" + v + "\"")
    None => ()
  }
  match self.dialogue_ref {
    Some(v) => lines.push("dialogue_ref: \"" + v + "\"")
    None => ()
  }
  match self.emission.docs_ref {
    Some(v) => lines.push("docs_ref: \"" + v + "\"")
    None => ()
  }
  match self.emission.gallery_ref {
    Some(v) => lines.push("gallery_ref: \"" + v + "\"")
    None => ()
  }
  match self.emission.wasm_plugin_ref {
    Some(v) => lines.push("wasm_plugin_ref: \"" + v + "\"")
    None => ()
  }
  match self.emission.deploy_queue_ref {
    Some(v) => lines.push("deploy_queue_ref: \"" + v + "\"")
    None => ()
  }
  lines
}

///|
pub fn LspContractBlock::invert(self : LspContractBlock) -> LspContractBlock {
  {
    function_name: self.inverse_function,
    inverse_function: self.function_name,
    role: match self.role {
      Mulsp => Muyata
      Muyata => Mulsp
    },
    protocol: self.inverse_protocol,
    inverse_protocol: self.protocol,
    seed: self.inverse_seed,
    inverse_seed: self.seed,
    can_fail: self.can_fail,
  }
}

///|
pub fn LspContractBlock::to_protocol_lines(self : LspContractBlock) -> Array[String] {
  [
    "@pattern lsp.dual.contract",
    "@function " + self.function_name,
    "@inverse " + self.inverse_function,
    "@role " + self.role.to_string(),
    "@protocol " + self.protocol,
    "@seed " + self.seed.to_string(),
    "@can_fail " + (if self.can_fail { "true" } else { "false" }),
  ]
}

///|
pub fn lsp_dual_spec() -> Array[LspFnDualSpec] {
  [
    {
      name: "frame_read",
      inverse_name: "frame_write",
      category: Framing,
      func_type: Codec,
      can_fail: true,
      mulsp_protocol: "compose.frame.pull",
      muyata_protocol: "ingest.frame.push",
      mulsp_seed: 5,
      muyata_seed: 5,
    },
    {
      name: "frame_write",
      inverse_name: "frame_read",
      category: Framing,
      func_type: Codec,
      can_fail: false,
      mulsp_protocol: "compose.frame.push",
      muyata_protocol: "ingest.frame.pull",
      mulsp_seed: 5,
      muyata_seed: 5,
    },
    {
      name: "frame_drain",
      inverse_name: "LspClient::ingest",
      category: Framing,
      func_type: Router,
      can_fail: false,
      mulsp_protocol: "compose.frame.batch",
      muyata_protocol: "ingest.frame.batch",
      mulsp_seed: 4,
      muyata_seed: 6,
    },
    {
      name: "bytes_to_str_pub",
      inverse_name: "LspClient::encode",
      category: Framing,
      func_type: Utility,
      can_fail: false,
      mulsp_protocol: "compose.payload.decode",
      muyata_protocol: "ingest.payload.encode",
      mulsp_seed: 2,
      muyata_seed: 2,
    },
    {
      name: "slice_pub",
      inverse_name: "LspClient::pending_bytes",
      category: Framing,
      func_type: Utility,
      can_fail: false,
      mulsp_protocol: "compose.window.slice",
      muyata_protocol: "ingest.window.observe",
      mulsp_seed: 2,
      muyata_seed: 2,
    },
    {
      name: "parse_message",
      inverse_name: "LspClient::encode",
      category: Message,
      func_type: Parser,
      can_fail: false,
      mulsp_protocol: "compose.message.route",
      muyata_protocol: "ingest.message.normalize",
      mulsp_seed: 4,
      muyata_seed: 3,
    },
    {
      name: "parse_frame",
      inverse_name: "LspClient::parse",
      category: Message,
      func_type: Parser,
      can_fail: false,
      mulsp_protocol: "compose.message.from_frame",
      muyata_protocol: "ingest.message.from_wire",
      mulsp_seed: 4,
      muyata_seed: 4,
    },
    {
      name: "LspClientOps::new",
      inverse_name: "LspClient::new",
      category: ClientOps,
      func_type: Constructor,
      can_fail: false,
      mulsp_protocol: "compose.ops.seed",
      muyata_protocol: "ingest.ops.bind",
      mulsp_seed: 3,
      muyata_seed: 3,
    },
    {
      name: "LspClientOps::json_rpc_core",
      inverse_name: "LspClient::proxy",
      category: ClientOps,
      func_type: Constructor,
      can_fail: false,
      mulsp_protocol: "compose.ops.jsonrpc",
      muyata_protocol: "ingest.ops.proxy",
      mulsp_seed: 3,
      muyata_seed: 3,
    },
    {
      name: "LspClientOps::proxy",
      inverse_name: "LspClient::proxy",
      category: ClientOps,
      func_type: Constructor,
      can_fail: false,
      mulsp_protocol: "compose.ops.proxy",
      muyata_protocol: "ingest.ops.proxy",
      mulsp_seed: 3,
      muyata_seed: 3,
    },
    {
      name: "LspClientOps::claude_process",
      inverse_name: "LspClient::claude_process",
      category: ClientOps,
      func_type: Constructor,
      can_fail: false,
      mulsp_protocol: "compose.ops.claude",
      muyata_protocol: "ingest.ops.claude",
      mulsp_seed: 3,
      muyata_seed: 3,
    },
    {
      name: "LspClient::new",
      inverse_name: "LspClientOps::new",
      category: ClientRuntime,
      func_type: Constructor,
      can_fail: false,
      mulsp_protocol: "compose.client.seed",
      muyata_protocol: "ingest.client.attach",
      mulsp_seed: 3,
      muyata_seed: 3,
    },
    {
      name: "LspClient::proxy",
      inverse_name: "LspClientOps::proxy",
      category: ClientRuntime,
      func_type: Constructor,
      can_fail: false,
      mulsp_protocol: "compose.client.proxy",
      muyata_protocol: "ingest.client.proxy",
      mulsp_seed: 3,
      muyata_seed: 3,
    },
    {
      name: "LspClient::claude_process",
      inverse_name: "LspClientOps::claude_process",
      category: ClientRuntime,
      func_type: Constructor,
      can_fail: false,
      mulsp_protocol: "compose.client.claude",
      muyata_protocol: "ingest.client.claude",
      mulsp_seed: 3,
      muyata_seed: 3,
    },
    {
      name: "LspClient::impl_id",
      inverse_name: "LspClient::impl_id",
      category: ClientRuntime,
      func_type: Observer,
      can_fail: false,
      mulsp_protocol: "compose.client.identity",
      muyata_protocol: "ingest.client.identity",
      mulsp_seed: 1,
      muyata_seed: 1,
    },
    {
      name: "LspClient::pending_bytes",
      inverse_name: "slice_pub",
      category: ClientRuntime,
      func_type: Observer,
      can_fail: false,
      mulsp_protocol: "compose.client.buffer.read",
      muyata_protocol: "ingest.client.buffer.window",
      mulsp_seed: 2,
      muyata_seed: 2,
    },
    {
      name: "LspClient::ingest",
      inverse_name: "frame_drain",
      category: ClientRuntime,
      func_type: Router,
      can_fail: false,
      mulsp_protocol: "compose.client.ingest",
      muyata_protocol: "ingest.client.drain",
      mulsp_seed: 6,
      muyata_seed: 4,
    },
    {
      name: "LspClient::encode",
      inverse_name: "parse_message",
      category: ClientRuntime,
      func_type: Codec,
      can_fail: false,
      mulsp_protocol: "compose.client.encode",
      muyata_protocol: "ingest.client.decode",
      mulsp_seed: 4,
      muyata_seed: 4,
    },
    {
      name: "LspClient::parse",
      inverse_name: "parse_frame",
      category: ClientRuntime,
      func_type: Parser,
      can_fail: false,
      mulsp_protocol: "compose.client.parse",
      muyata_protocol: "ingest.client.resolve",
      mulsp_seed: 4,
      muyata_seed: 4,
    },
    {
      name: "ScanReport::summary",
      inverse_name: "scan_str",
      category: Scanner,
      func_type: Observer,
      can_fail: false,
      mulsp_protocol: "compose.scan.summary",
      muyata_protocol: "ingest.scan.summary",
      mulsp_seed: 2,
      muyata_seed: 2,
    },
    {
      name: "ScanReport::counts",
      inverse_name: "scan_bytes",
      category: Scanner,
      func_type: Observer,
      can_fail: false,
      mulsp_protocol: "compose.scan.counts",
      muyata_protocol: "ingest.scan.counts",
      mulsp_seed: 2,
      muyata_seed: 2,
    },
    {
      name: "scan_bytes",
      inverse_name: "scan_str",
      category: Scanner,
      func_type: Parser,
      can_fail: false,
      mulsp_protocol: "compose.scan.bytes",
      muyata_protocol: "ingest.scan.bytes",
      mulsp_seed: 5,
      muyata_seed: 5,
    },
    {
      name: "scan_str",
      inverse_name: "scan_bytes",
      category: Scanner,
      func_type: Parser,
      can_fail: false,
      mulsp_protocol: "compose.scan.str",
      muyata_protocol: "ingest.scan.str",
      mulsp_seed: 5,
      muyata_seed: 5,
    },
  ]
}

///|
pub fn lsp_spec_by_category(cat : LspCategory) -> Array[LspFnDualSpec] {
  let out : Array[LspFnDualSpec] = []
  for entry in lsp_dual_spec() {
    if entry.category == cat {
      out.push(entry)
    }
  }
  out
}

///|
pub fn lsp_spec_lookup(name : String) -> LspFnDualSpec? {
  for entry in lsp_dual_spec() {
    if entry.name == name {
      return Some(entry)
    }
  }
  None
}

///|
pub fn wrap_mulsp(name : String) -> LspContractBlock? {
  match lsp_spec_lookup(name) {
    None => None
    Some(entry) =>
      Some({
        function_name: entry.name,
        inverse_function: entry.inverse_name,
        role: Mulsp,
        protocol: entry.mulsp_protocol,
        inverse_protocol: entry.muyata_protocol,
        seed: entry.mulsp_seed,
        inverse_seed: entry.muyata_seed,
        can_fail: entry.can_fail,
      })
  }
}

///|
pub fn wrap_muyata(name : String) -> LspContractBlock? {
  match wrap_mulsp(name) {
    None => None
    Some(block) => Some(block.invert())
  }
}

///|
pub fn bind_dual_contract(
  function_name : String,
  contract_id : String,
  test_result_ref : String?,
  coverage_ref : String?,
  proof_ref : String?,
  dialogue_ref : String?,
  obligations : Array[LspProofObligation],
  emission : LspEmissionSurface,
  side_effect_observed? : Bool = true,
) -> LspDualContractBinding? {
  match wrap_mulsp(function_name) {
    None => None
    Some(mulsp_block) =>
      Some({
        contract_id,
        function_name: mulsp_block.function_name,
        inverse_function: mulsp_block.inverse_function,
        test_result_ref,
        coverage_ref,
        proof_ref,
        dialogue_ref,
        side_effect_observed,
        obligations,
        emission,
      })
  }
}
