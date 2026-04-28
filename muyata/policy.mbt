///|
/// Muyata executable policy primitives for FST workload governance.

///|
pub(all) struct MuyataFstPolicy {
  max_fsts_per_shard : Int
  require_append_only_compose : Bool
} derive(Debug)

///|
pub fn default_fst_policy() -> MuyataFstPolicy {
  { max_fsts_per_shard: 8, require_append_only_compose: true }
}

///|
pub(all) struct MuyataFstShard {
  shard_id : String
  fsts : Array[String]
  is_overflow : Bool
} derive(Debug)

///|
pub fn split_fst_shards(
  fsts : Array[String],
  policy? : MuyataFstPolicy = default_fst_policy(),
) -> Array[MuyataFstShard] {
  let cap = if policy.max_fsts_per_shard > 0 {
    policy.max_fsts_per_shard
  } else {
    8
  }
  let shards : Array[MuyataFstShard] = []
  if fsts.length() == 0 {
    return shards
  }
  let mut idx = 0
  let mut shard_no = 0
  while idx < fsts.length() {
    let chunk : Array[String] = []
    let mut c = 0
    while idx < fsts.length() && c < cap {
      chunk.push(fsts[idx])
      idx = idx + 1
      c = c + 1
    }
    shards.push({
      shard_id: "muyata-shard-" + shard_no.to_string(),
      fsts: chunk,
      is_overflow: shard_no > 0,
    })
    shard_no = shard_no + 1
  }
  shards
}

///|
pub(all) struct ComposeStep {
  seq : Int
  op : String
  left_ref : String
  right_ref : String
  out_ref : String
  prev_step_ref : String?
  step_ref : String
} derive(Debug)

///|
pub(all) struct ComposeChain {
  chain_id : String
  steps : Array[ComposeStep]
} derive(Debug)

///|
fn mk_step_ref(chain_id : String, seq : Int, op : String) -> String {
  "compose://" + chain_id + "/" + seq.to_string() + "/" + op
}

///|
pub fn ComposeChain::new(chain_id : String) -> ComposeChain {
  { chain_id, steps: [] }
}

///|
pub fn ComposeChain::append_op(
  self : ComposeChain,
  op : String,
  left_ref : String,
  right_ref : String,
  out_ref : String,
) -> ComposeChain {
  let seq = self.steps.length() + 1
  let prev_step_ref = match self.steps {
    [.., last] => Some(last.step_ref)
    [] => None
  }
  let step_ref = mk_step_ref(self.chain_id, seq, op)
  let steps = self.steps
  steps.push({
    seq,
    op,
    left_ref,
    right_ref,
    out_ref,
    prev_step_ref,
    step_ref,
  })
  { ..self, steps }
}

///|
pub fn ComposeChain::is_append_only(self : ComposeChain) -> Bool {
  let mut expect_seq = 1
  let mut prev : String? = None
  for step in self.steps {
    if step.seq != expect_seq {
      return false
    }
    if step.prev_step_ref != prev {
      return false
    }
    prev = Some(step.step_ref)
    expect_seq = expect_seq + 1
  }
  true
}

///|
pub fn validate_compose_chain(
  chain : ComposeChain,
  policy? : MuyataFstPolicy = default_fst_policy(),
) -> Bool {
  if !policy.require_append_only_compose {
    return true
  }
  chain.is_append_only()
}

///|
pub fn ComposeChain::to_muon_lines(self : ComposeChain) -> Array[String] {
  let lines = [
    "kind: :muyata_compose_chain",
    "chain_id: \"" + self.chain_id + "\"",
    "@append_only " + (if self.is_append_only() { "true" } else { "false" }),
    "@step_count " + self.steps.length().to_string(),
  ]
  for step in self.steps {
    lines.push("@step.seq " + step.seq.to_string())
    lines.push("@step.op " + step.op)
    lines.push("@step.left_ref " + step.left_ref)
    lines.push("@step.right_ref " + step.right_ref)
    lines.push("@step.out_ref " + step.out_ref)
    match step.prev_step_ref {
      Some(v) => lines.push("@step.prev_ref " + v)
      None => lines.push("@step.prev_ref root")
    }
    lines.push("@step.ref " + step.step_ref)
  }
  lines
}

///|
/// Fail-close primitive: emit runtime coredump and close workload branch.
///
/// Returns None when append-only compose provenance is invalid.
pub fn emit_fail_close_coredump(
  chain : ComposeChain,
  loci_id : String,
  branch_id : String,
  contract_id : String,
  transducer_id : String,
  state_tag : String,
  parent_chain_ref : String,
  loci_return_ref : String,
  wasm_module_ref : String,
  pending_cave_count : Int,
  secret_zone_refs? : Array[String] = [],
  policy? : MuyataFstPolicy = default_fst_policy(),
) -> @proto.RuntimeCoreDump? {
  if !validate_compose_chain(chain, policy=policy) {
    return None
  }
  let compose_chain_ref = match chain.steps {
    [.., last] => last.step_ref
    [] => "compose://" + chain.chain_id + "/root"
  }
  Some(
    @proto.RuntimeCoreDump::new(
      loci_id,
      branch_id,
      contract_id,
      transducer_id,
      chain.steps.length(),
      state_tag,
      compose_chain_ref,
      parent_chain_ref,
      loci_return_ref,
      wasm_module_ref,
      "policy://MUYATA_POLICY/0.1",
      pending_cave_count,
      secret_zone_refs=secret_zone_refs,
    ),
  )
}
