///|
/// Runtime coredump primitive for fail-close behavior.

///|
pub(all) struct RuntimeCoreDump {
  loci_id : String
  branch_id : String
  contract_id : String
  transducer_id : String
  seq_head : Int
  state_tag : String
  compose_chain_ref : String
  parent_chain_ref : String
  loci_return_ref : String
  wasm_module_ref : String
  policy_ref : String
  pending_cave_count : Int
  secret_zone_refs : Array[String]
  closed : Bool
} derive(Debug)

///|
pub fn RuntimeCoreDump::new(
  loci_id : String,
  branch_id : String,
  contract_id : String,
  transducer_id : String,
  seq_head : Int,
  state_tag : String,
  compose_chain_ref : String,
  parent_chain_ref : String,
  loci_return_ref : String,
  wasm_module_ref : String,
  policy_ref : String,
  pending_cave_count : Int,
  secret_zone_refs? : Array[String] = [],
) -> RuntimeCoreDump {
  {
    loci_id,
    branch_id,
    contract_id,
    transducer_id,
    seq_head,
    state_tag,
    compose_chain_ref,
    parent_chain_ref,
    loci_return_ref,
    wasm_module_ref,
    policy_ref,
    pending_cave_count,
    secret_zone_refs,
    closed: true,
  }
}

///|
pub fn RuntimeCoreDump::to_muon_lines(self : RuntimeCoreDump) -> Array[String] {
  let lines = [
    "kind: :runtime_coredump",
    "loci_id: \"" + self.loci_id + "\"",
    "branch_id: \"" + self.branch_id + "\"",
    "contract_id: \"" + self.contract_id + "\"",
    "@transducer_id " + self.transducer_id,
    "@seq_head " + self.seq_head.to_string(),
    "@state_tag " + self.state_tag,
    "@compose_chain_ref " + self.compose_chain_ref,
    "@parent_chain_ref " + self.parent_chain_ref,
    "@loci_return_ref " + self.loci_return_ref,
    "@wasm_module_ref " + self.wasm_module_ref,
    "@policy_ref " + self.policy_ref,
    "@pending_cave_count " + self.pending_cave_count.to_string(),
    "@close_after_dump " + (if self.closed { "true" } else { "false" }),
    "@raw_secret_export false",
  ]
  for zone_ref in self.secret_zone_refs {
    lines.push("@secret_zone_ref " + zone_ref)
  }
  lines
}
