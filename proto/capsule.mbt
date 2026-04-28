///|
/// Contract capsule primitive.
///
/// This is the distributed replacement for single-server dynamic engines:
/// - root of truth is MuON lines, not JSON-LD payload glue
/// - brokering is compile-time/runtime capsule routing, not central hooks
/// - output artifact is wasm bundle metadata tied to loci dropbox lineage

///|
pub(all) enum CapsuleCompileStatus {
  Deferred
  Queued
  Compiled
  Published
  Failed
} derive(Eq, Debug)

///|
pub(all) struct CapsuleArtifact {
  wasm_ref : String?
  manifest_ref : String?
  gallery_ref : String?
} derive(Debug)

///|
pub(all) struct ContractCapsule {
  capsule_id : String
  loci_id : String
  method_name : String
  inverse_method : String
  request_id : String
  dropbox_ref : String
  compiler_unit : String
  mulsp_id : String
  muyata_profile : String
  obligations : Array[String]
  root_muon : Array[String]
  mut compile_status : CapsuleCompileStatus
  mut artifact : CapsuleArtifact
  cavity : Array[Byte]
} derive(Debug)

///|
fn capsule_compile_status_text(status : CapsuleCompileStatus) -> String {
  match status {
    Deferred => "deferred"
    Queued => "queued"
    Compiled => "compiled"
    Published => "published"
    Failed => "failed"
  }
}

// Fixed-size capsule layout (deterministic, wasm-like constraints)
let capsule_fixed_magic_width : Int = 8
let capsule_fixed_id_width : Int = 64
let capsule_fixed_method_width : Int = 48
let capsule_fixed_ref_width : Int = 96
let capsule_fixed_status_width : Int = 16
let capsule_fixed_obligation_count_width : Int = 8
let capsule_fixed_obligation_slots : Int = 8
let capsule_fixed_obligation_width : Int = 48
let capsule_fixed_wire_bytes : Int = 1024
let capsule_fixed_cavity_bytes : Int = 1024 * 1024

///|
pub fn capsule_wire_size() -> Int {
  capsule_fixed_wire_bytes
}

///|
pub fn capsule_cavity_size() -> Int {
  capsule_fixed_cavity_bytes
}

///|
fn capsule_non_blank(s : String) -> Bool {
  s.length() > 0
}

///|
fn capsule_has_ref(v : String?) -> Bool {
  match v {
    Some(s) => capsule_non_blank(s)
    None => false
  }
}

///|
pub fn ContractCapsule::new(
  capsule_id : String,
  loci_id : String,
  method_name : String,
  inverse_method : String,
  request_id : String,
  dropbox_ref : String,
  compiler_unit : String,
  mulsp_id : String,
  muyata_profile : String,
  obligations? : Array[String] = [],
) -> ContractCapsule {
  let root_muon = [
    "kind: :lang_contract_capsule",
    "binding_model: \"muon -> compile broker -> wasm artifact\"",
    "capsule_id: \"" + capsule_id + "\"",
    "loci_id: \"" + loci_id + "\"",
    "@method " + method_name,
    "@inverse " + inverse_method,
    "@request_id " + request_id,
    "@dropbox_ref " + dropbox_ref,
    "@compiler_unit " + compiler_unit,
    "@mulsp_id " + mulsp_id,
    "@muyata_profile " + muyata_profile,
  ]
  {
    capsule_id,
    loci_id,
    method_name,
    inverse_method,
    request_id,
    dropbox_ref,
    compiler_unit,
    mulsp_id,
    muyata_profile,
    obligations,
    root_muon,
    compile_status: Deferred,
    artifact: { wasm_ref: None, manifest_ref: None, gallery_ref: None },
    cavity: Array::make(capsule_fixed_cavity_bytes, b'\x00'),
  }
}

///|
pub fn ContractCapsule::for_lsp_method(
  loci_id : String,
  method_name : String,
  inverse_method : String,
  request_id : String,
  dropbox_ref : String,
  compiler_unit? : String = "lang.compiler",
) -> ContractCapsule {
  let capsule_id = "capsule:" + loci_id + ":" + method_name + ":" + request_id
  let mulsp_id = "lang:lsp:" + method_name + ":" + request_id
  ContractCapsule::new(
    capsule_id,
    loci_id,
    method_name,
    inverse_method,
    request_id,
    dropbox_ref,
    compiler_unit,
    mulsp_id,
    "lang/generic/lsp",
    obligations=[
      "obl-dropbox-lineage-bound",
      "obl-broker-compile-queued",
      "obl-wasm-artifact-emitted",
    ],
  )
}

///|
/// Core procsi capsule contract.
///
/// Procsi is reserved as a core capsule/plugin. Rotation must be explicit
/// through a handler-effect reference and should target a WASI surface.
pub fn ContractCapsule::for_procsi_core(
  loci_id : String,
  request_id : String,
  dropbox_ref : String,
  handler_effect_ref : String,
  old_procsi_ref : String?,
  new_procsi_ref : String,
) -> ContractCapsule {
  let capsule_id = "capsule:" + loci_id + ":procsi.core:" + request_id
  let capsule = ContractCapsule::new(
    capsule_id,
    loci_id,
    "procsi.core",
    "procsi.core.replace",
    request_id,
    dropbox_ref,
    "lang.compiler.procsi",
    "lang:procsi:core:" + request_id,
    "lang/procsi/wasi",
    obligations=[
      "obl-procsi-core-reserved",
      "obl-procsi-non-clobber-enforced",
      "obl-procsi-replace-handler-effect",
      "obl-procsi-wasi-surface",
      "obl-procsi-secret-safe-rotation",
    ],
  )
  capsule.root_muon.push("@core_capsule true")
  capsule.root_muon.push("@wasi_enabled true")
  capsule.root_muon.push("@outer_layer app")
  capsule.root_muon.push("@app_kernel_surface ai_only_append_only_muon")
  capsule.root_muon.push("@handler_effect_ref " + handler_effect_ref)
  capsule.root_muon.push("@new_procsi_ref " + new_procsi_ref)
  match old_procsi_ref {
    Some(v) => capsule.root_muon.push("@old_procsi_ref " + v)
    None => ()
  }
  capsule
}

///|
pub fn ContractCapsule::queue_compile(self : ContractCapsule) -> Unit {
  self.compile_status = Queued
}

///|
pub fn ContractCapsule::mark_compiled(
  self : ContractCapsule,
  wasm_ref : String,
  manifest_ref : String,
  gallery_ref : String?,
) -> Unit {
  self.artifact = {
    wasm_ref: Some(wasm_ref),
    manifest_ref: Some(manifest_ref),
    gallery_ref,
  }
  self.compile_status = Compiled
}

///|
pub fn ContractCapsule::mark_published(self : ContractCapsule) -> Bool {
  if self.can_publish() {
    self.compile_status = Published
    true
  } else {
    false
  }
}

///|
pub fn ContractCapsule::broker_ready(self : ContractCapsule) -> Bool where {
  proof_ensure: result => !result || capsule_non_blank(self.dropbox_ref),
  proof_ensure: result => !result || capsule_non_blank(self.compiler_unit),
  proof_ensure: result => !result || capsule_non_blank(self.request_id),
} {
  capsule_non_blank(self.loci_id) &&
  capsule_non_blank(self.method_name) &&
  capsule_non_blank(self.inverse_method) &&
  capsule_non_blank(self.request_id) &&
  capsule_non_blank(self.dropbox_ref) &&
  capsule_non_blank(self.compiler_unit)
}

///|
pub fn ContractCapsule::can_publish(self : ContractCapsule) -> Bool where {
  proof_ensure: result => !result || self.compile_status == Compiled || self.compile_status == Published,
} {
  self.broker_ready() &&
  (self.compile_status == Compiled || self.compile_status == Published) &&
  capsule_has_ref(self.artifact.wasm_ref) &&
  capsule_has_ref(self.artifact.manifest_ref)
}

///|
pub fn ContractCapsule::to_muon_lines(self : ContractCapsule) -> Array[String] {
  let lines = self.root_muon.copy()
  lines.push("@compile_status " + capsule_compile_status_text(self.compile_status))
  for obligation in self.obligations {
    lines.push("@obligation " + obligation)
  }
  match self.artifact.wasm_ref {
    Some(v) => lines.push("wasm_ref: \"" + v + "\"")
    None => ()
  }
  match self.artifact.manifest_ref {
    Some(v) => lines.push("manifest_ref: \"" + v + "\"")
    None => ()
  }
  match self.artifact.gallery_ref {
    Some(v) => lines.push("gallery_ref: \"" + v + "\"")
    None => ()
  }
  lines
}

///|
fn capsule_ascii_bytes(s : String) -> Array[Byte] {
  let out : Array[Byte] = []
  for ch in s {
    let cp = ch.to_int()
    if cp < 0x80 {
      out.push(cp.to_byte())
    } else {
      out.push(b'?')
    }
  }
  out
}

///|
fn capsule_write_padded_ascii(
  out : Array[Byte],
  start : Int,
  width : Int,
  value : String,
) -> Unit {
  let bytes = capsule_ascii_bytes(value)
  let mut i = 0
  while i < width {
    out[start + i] = b'\x00'
    i = i + 1
  }
  let mut j = 0
  let max = if bytes.length() < width { bytes.length() } else { width }
  while j < max {
    out[start + j] = bytes[j]
    j = j + 1
  }
}

///|
fn capsule_field_offsets() -> Array[(Int, Int)] {
  let widths = [
    capsule_fixed_magic_width, // magic/version
    capsule_fixed_id_width, // capsule_id
    capsule_fixed_id_width, // loci_id
    capsule_fixed_method_width, // method_name
    capsule_fixed_method_width, // inverse_method
    capsule_fixed_method_width, // request_id
    capsule_fixed_ref_width, // dropbox_ref
    capsule_fixed_method_width, // compiler_unit
    capsule_fixed_ref_width, // mulsp_id
    capsule_fixed_method_width, // muyata_profile
    capsule_fixed_status_width, // compile_status
    capsule_fixed_obligation_count_width, // obligation_count
  ]
  let out : Array[(Int, Int)] = []
  let mut cursor = 0
  for w in widths {
    out.push((cursor, w))
    cursor = cursor + w
  }
  // fixed obligation slots
  let mut k = 0
  while k < capsule_fixed_obligation_slots {
    out.push((cursor, capsule_fixed_obligation_width))
    cursor = cursor + capsule_fixed_obligation_width
    k = k + 1
  }
  out
}

///|
pub fn ContractCapsule::to_fixed_bytes(self : ContractCapsule) -> Array[Byte] {
  let out = Array::make(capsule_fixed_wire_bytes, b'\x00')
  let offsets = capsule_field_offsets()
  capsule_write_padded_ascii(out, offsets[0].0, offsets[0].1, "capsule1")
  capsule_write_padded_ascii(out, offsets[1].0, offsets[1].1, self.capsule_id)
  capsule_write_padded_ascii(out, offsets[2].0, offsets[2].1, self.loci_id)
  capsule_write_padded_ascii(out, offsets[3].0, offsets[3].1, self.method_name)
  capsule_write_padded_ascii(out, offsets[4].0, offsets[4].1, self.inverse_method)
  capsule_write_padded_ascii(out, offsets[5].0, offsets[5].1, self.request_id)
  capsule_write_padded_ascii(out, offsets[6].0, offsets[6].1, self.dropbox_ref)
  capsule_write_padded_ascii(out, offsets[7].0, offsets[7].1, self.compiler_unit)
  capsule_write_padded_ascii(out, offsets[8].0, offsets[8].1, self.mulsp_id)
  capsule_write_padded_ascii(out, offsets[9].0, offsets[9].1, self.muyata_profile)
  capsule_write_padded_ascii(
    out,
    offsets[10].0,
    offsets[10].1,
    capsule_compile_status_text(self.compile_status),
  )
  capsule_write_padded_ascii(
    out,
    offsets[11].0,
    offsets[11].1,
    self.obligations.length().to_string(),
  )
  let mut i = 0
  while i < capsule_fixed_obligation_slots {
    let slot = offsets[12 + i]
    let value = if i < self.obligations.length() { self.obligations[i] } else { "" }
    capsule_write_padded_ascii(out, slot.0, slot.1, value)
    i = i + 1
  }
  out
}

///|
pub fn ContractCapsule::cavity_write(
  self : ContractCapsule,
  offset : Int,
  data : Array[Byte],
) -> Bool {
  if offset < 0 || data.length() < 0 {
    return false
  }
  if offset + data.length() > self.cavity.length() {
    return false
  }
  let mut i = 0
  while i < data.length() {
    self.cavity[offset + i] = data[i]
    i = i + 1
  }
  true
}

///|
pub fn ContractCapsule::cavity_read(
  self : ContractCapsule,
  offset : Int,
  length : Int,
) -> Array[Byte] {
  if offset < 0 || length <= 0 || offset + length > self.cavity.length() {
    return []
  }
  let out = Array::make(length, b'\x00')
  let mut i = 0
  while i < length {
    out[i] = self.cavity[offset + i]
    i = i + 1
  }
  out
}

///|
/// Mount a protected in-memory snapshot (e.g. ~/.codex material) into the
/// fixed cavity without any filesystem writes.
pub fn ContractCapsule::mount_protected_snapshot(
  self : ContractCapsule,
  snapshot : Array[Byte],
) -> Bool {
  if snapshot.length() > self.cavity.length() {
    return false
  }
  let mut i = 0
  while i < self.cavity.length() {
    self.cavity[i] = b'\x00'
    i = i + 1
  }
  let mut j = 0
  while j < snapshot.length() {
    self.cavity[j] = snapshot[j]
    j = j + 1
  }
  true
}

///|
/// Zero the full protected cavity in-memory.
pub fn ContractCapsule::wipe_cavity(self : ContractCapsule) -> Unit {
  let mut i = 0
  while i < self.cavity.length() {
    self.cavity[i] = b'\x00'
    i = i + 1
  }
}
