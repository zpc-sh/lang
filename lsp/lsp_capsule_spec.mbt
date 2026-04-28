///|
/// Capsule-oriented aggregation for the full LSP dual spec.
///
/// This bridges `lsp_dual_spec()` entries into `@proto.ContractCapsule`
/// instances and keeps a central table that can be executed, proven,
/// documented, and presented as MuON-like lines.

///|
pub(all) struct LspCapsuleRow {
  function_name : String
  inverse_name : String
  category : LspCategory
  func_type : LspFuncType
  can_fail : Bool
  wasi_world : String
  wasm_target : String
  oci_media_type : String
  oci_compliant : Bool
  capsule : @proto.ContractCapsule
} derive(Debug)

///|
fn category_tag(category : LspCategory) -> String {
  match category {
    Framing => "framing"
    Message => "message"
    ClientOps => "client_ops"
    ClientRuntime => "client_runtime"
    Scanner => "scanner"
  }
}

///|
fn func_type_tag(func_type : LspFuncType) -> String {
  match func_type {
    Constructor => "constructor"
    Codec => "codec"
    Parser => "parser"
    Router => "router"
    Observer => "observer"
    Utility => "utility"
  }
}

///|
fn capsule_loci_id(spec : LspFnDualSpec) -> String {
  "loci/lang/lsp/" + category_tag(spec.category) + "/" + spec.name
}

///|
fn capsule_dropbox_ref(spec : LspFnDualSpec, request_id : String) -> String {
  "dropbox://loci/lang/lsp/" + category_tag(spec.category) + "/" + spec.name + "/" + request_id
}

///|
fn capsule_request_id(spec : LspFnDualSpec, run_id : String) -> String {
  "req-" + run_id + "-" + spec.name
}

///|
fn capsule_oci_media_type(_spec : LspFnDualSpec) -> String {
  "application/vnd.zpc.lsp-function.wasm.layer.v1+wasm"
}

///|
pub fn lsp_capsule_row(spec : LspFnDualSpec, run_id : String) -> LspCapsuleRow {
  let request_id = capsule_request_id(spec, run_id)
  let capsule = @proto.ContractCapsule::for_lsp_method(
    capsule_loci_id(spec),
    spec.name,
    spec.inverse_name,
    request_id,
    capsule_dropbox_ref(spec, request_id),
    compiler_unit="lang.compiler.lsp",
  )
  capsule.obligations.push("obl-lsp-category-" + category_tag(spec.category))
  capsule.obligations.push("obl-lsp-func-type-" + func_type_tag(spec.func_type))
  if spec.can_fail {
    capsule.obligations.push("obl-lsp-can-fail")
  }
  capsule.obligations.push("obl-lsp-wasi-support")
  capsule.obligations.push("obl-lsp-oci-compliance")
  capsule.obligations.push("obl-lsp-loci-identity")
  {
    function_name: spec.name,
    inverse_name: spec.inverse_name,
    category: spec.category,
    func_type: spec.func_type,
    can_fail: spec.can_fail,
    wasi_world: "zpc:locus@0.1.0/locus-world",
    wasm_target: "wasm32-wasi",
    oci_media_type: capsule_oci_media_type(spec),
    oci_compliant: true,
    capsule,
  }
}

///|
pub fn lsp_capsule_table(run_id? : String = "spec") -> Array[LspCapsuleRow] {
  let rows : Array[LspCapsuleRow] = []
  for spec in lsp_dual_spec() {
    rows.push(lsp_capsule_row(spec, run_id))
  }
  rows
}

///|
pub fn lsp_capsule_lookup(
  function_name : String,
  run_id? : String = "spec",
) -> LspCapsuleRow? {
  for row in lsp_capsule_table(run_id=run_id) {
    if row.function_name == function_name {
      return Some(row)
    }
  }
  None
}

///|
pub fn LspCapsuleRow::is_provable(self : LspCapsuleRow) -> Bool where {
  proof_ensure: result => !result || self.capsule.broker_ready(),
} {
  self.capsule.broker_ready() &&
  self.capsule.obligations.length() >= 7 &&
  self.wasi_world.length() > 0 &&
  self.wasm_target.length() > 0 &&
  self.oci_media_type.length() > 0 &&
  self.oci_compliant
}

///|
pub fn lsp_capsule_table_provable(run_id? : String = "spec") -> Bool where {
  proof_ensure: result => !result || lsp_capsule_table(run_id=run_id).length() == lsp_dual_spec().length(),
} {
  let rows = lsp_capsule_table(run_id=run_id)
  if rows.length() != lsp_dual_spec().length() {
    return false
  }
  for row in rows {
    if !row.is_provable() {
      return false
    }
  }
  true
}

///|
pub fn lsp_capsule_registry_lines(run_id? : String = "spec") -> Array[String] {
  let rows = lsp_capsule_table(run_id=run_id)
  let lines = [
    "kind: :lsp_capsule_registry",
    "binding_model: \"all_lsp_functions -> per_function_wasm_wasi_capsule_with_loci_oci_contract\"",
    "@total_functions " + rows.length().to_string(),
    "@table_provable " + (if lsp_capsule_table_provable(run_id=run_id) { "true" } else { "false" }),
  ]
  for row in rows {
    lines.push("@entry " + row.function_name + " -> " + row.inverse_name)
    lines.push("@category " + category_tag(row.category))
    lines.push("@func_type " + func_type_tag(row.func_type))
    lines.push("@capsule_id " + row.capsule.capsule_id)
    lines.push("@request_id " + row.capsule.request_id)
    lines.push("@wasi_world " + row.wasi_world)
    lines.push("@wasm_target " + row.wasm_target)
    lines.push("@oci_media_type " + row.oci_media_type)
    lines.push("@oci_compliant " + (if row.oci_compliant { "true" } else { "false" }))
  }
  lines
}

///|
pub fn lsp_capsule_function_lines(
  function_name : String,
  run_id? : String = "spec",
) -> Array[String]? {
  match lsp_capsule_lookup(function_name, run_id=run_id) {
    None => None
    Some(row) => {
      let lines = row.capsule.to_muon_lines()
      lines.push("@category " + category_tag(row.category))
      lines.push("@func_type " + func_type_tag(row.func_type))
      lines.push("@wasi_world " + row.wasi_world)
      lines.push("@wasm_target " + row.wasm_target)
      lines.push("@oci_media_type " + row.oci_media_type)
      lines.push("@oci_compliant " + (if row.oci_compliant { "true" } else { "false" }))
      Some(lines)
    }
  }
}
