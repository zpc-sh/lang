///|
test "capsule for lsp method is broker-ready and request-bound" {
  let capsule = ContractCapsule::for_lsp_method(
    "loci/lang/frame_read",
    "frame_read",
    "frame_write",
    "req-1",
    "dropbox://loci/lang/frame_read/req-1",
  )
  assert_true(capsule.broker_ready())
  assert_true(capsule.mulsp_id == "lang:lsp:frame_read:req-1")
  assert_true(capsule.compile_status == Deferred)
}

///|
test "capsule compile queue and publish gate" {
  let capsule = ContractCapsule::for_lsp_method(
    "loci/lang/parse",
    "parse_message",
    "encode",
    "req-2",
    "dropbox://loci/lang/parse/req-2",
  )
  capsule.queue_compile()
  assert_true(capsule.compile_status == Queued)
  assert_true(!capsule.can_publish())

  capsule.mark_compiled(
    "wasm://lang/lsp/parse_message.wasm",
    "manifest://lang/lsp/parse_message.muon",
    Some("gallery://lang/lsp/parse_message"),
  )
  assert_true(capsule.compile_status == Compiled)
  assert_true(capsule.can_publish())
  assert_true(capsule.mark_published())
  assert_true(capsule.compile_status == Published)
}

///|
test "capsule emits muon root lines" {
  let capsule = ContractCapsule::for_lsp_method(
    "loci/lang/scan",
    "scan_bytes",
    "scan_str",
    "req-3",
    "dropbox://loci/lang/scan/req-3",
  )
  let lines = capsule.to_muon_lines()
  assert_eq(lines[0], "kind: :lang_contract_capsule")
  assert_true(lines[3].has_prefix("loci_id:"))
  assert_true(lines[4].has_prefix("@method"))
  assert_true(lines[8].has_prefix("@compiler_unit"))
}

///|
test "capsule fixed wire size remains deterministic" {
  let capsule = ContractCapsule::for_lsp_method(
    "loci/lang/fixed",
    "frame_read",
    "frame_write",
    "req-4",
    "dropbox://loci/lang/fixed/req-4",
  )
  let bytes = capsule.to_fixed_bytes()
  assert_eq(bytes.length(), capsule_wire_size())
  capsule.queue_compile()
  let bytes2 = capsule.to_fixed_bytes()
  assert_eq(bytes2.length(), capsule_wire_size())
}

///|
test "capsule cavity has fixed size and bounded writes" {
  let capsule = ContractCapsule::for_lsp_method(
    "loci/lang/cavity",
    "scan_bytes",
    "scan_str",
    "req-5",
    "dropbox://loci/lang/cavity/req-5",
  )
  assert_eq(capsule.cavity.length(), capsule_cavity_size())
  assert_true(capsule.cavity_write(0, [0x41, 0x42, 0x43]))
  let got = capsule.cavity_read(0, 3)
  assert_eq(got.length(), 3)
  assert_eq(got[0], 0x41)
  assert_eq(got[1], 0x42)
  assert_eq(got[2], 0x43)
  assert_true(!capsule.cavity_write(capsule_cavity_size() - 1, [0x01, 0x02]))
}

///|
test "capsule mounts protected snapshot in memory only" {
  let capsule = ContractCapsule::for_lsp_method(
    "loci/lang/protected",
    "parse_message",
    "encode",
    "req-6",
    "dropbox://loci/lang/protected/req-6",
  )
  assert_eq(capsule_cavity_size(), 1024 * 1024)
  let snap : Array[Byte] = [0x7B, 0x22, 0x61, 0x22, 0x3A, 0x31, 0x7D] // {"a":1}
  assert_true(capsule.mount_protected_snapshot(snap))
  let got = capsule.cavity_read(0, snap.length())
  assert_eq(got.length(), snap.length())
  assert_eq(got[0], 0x7B)
  assert_eq(got[6], 0x7D)
  capsule.wipe_cavity()
  let wiped = capsule.cavity_read(0, 7)
  assert_eq(wiped[0], 0x00)
  assert_eq(wiped[6], 0x00)
}

///|
test "procsi core capsule emits reserved non-clobber replacement contract lines" {
  let capsule = ContractCapsule::for_procsi_core(
    "loci/lang/procsi",
    "req-7",
    "dropbox://loci/lang/procsi/req-7",
    "effect://handler/procsi-replace/1",
    Some("wasm://procsi/v1"),
    "wasm://procsi/v2",
  )
  assert_true(capsule.broker_ready())
  assert_eq(capsule.muyata_profile, "lang/procsi/wasi")
  let lines = capsule.to_muon_lines()
  assert_true(lines.contains("@core_capsule true"))
  assert_true(lines.contains("@wasi_enabled true"))
  assert_true(lines.contains("@outer_layer app"))
  assert_true(lines.contains("@app_kernel_surface ai_only_append_only_muon"))
  assert_true(lines.contains("@handler_effect_ref effect://handler/procsi-replace/1"))
}
