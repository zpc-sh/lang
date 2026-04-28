///|
test "capsule table covers full lsp dual spec" {
  let rows = @lsp.lsp_capsule_table()
  assert_eq(rows.length(), @lsp.lsp_dual_spec().length())
  assert_true(rows.length() > 20)
}

///|
test "capsule rows are request bound and broker ready" {
  for row in @lsp.lsp_capsule_table(run_id="r1") {
    assert_true(row.capsule.broker_ready())
    assert_true(row.capsule.request_id.has_prefix("req-r1-"))
    assert_true(row.capsule.method_name == row.function_name)
    assert_true(row.capsule.inverse_method == row.inverse_name)
    assert_eq(row.wasi_world, "zpc:locus@0.1.0/locus-world")
    assert_eq(row.wasm_target, "wasm32-wasi")
    assert_true(row.oci_compliant)
    assert_true(row.oci_media_type.has_prefix("application/vnd.zpc.lsp-function.wasm.layer.v1"))
  }
}

///|
test "capsule table is provable" {
  assert_true(@lsp.lsp_capsule_table_provable())
}

///|
test "capsule lookup returns central table entry" {
  match @lsp.lsp_capsule_lookup("frame_read", run_id="lookup") {
    None => fail("missing frame_read")
    Some(row) => {
      assert_eq(row.function_name, "frame_read")
      assert_eq(row.inverse_name, "frame_write")
      assert_true(row.capsule.capsule_id.has_prefix("capsule:loci/lang/lsp/"))
    }
  }
}

///|
test "capsule registry lines present aggregate view" {
  let lines = @lsp.lsp_capsule_registry_lines(run_id="present")
  assert_eq(lines[0], "kind: :lsp_capsule_registry")
  assert_true(lines[2].has_prefix("@total_functions "))
  assert_true(lines[3] == "@table_provable true")
  assert_true(lines.contains("@wasi_world zpc:locus@0.1.0/locus-world"))
  assert_true(lines.contains("@wasm_target wasm32-wasi"))
  assert_true(lines.contains("@oci_compliant true"))
}

///|
test "capsule function lines include capsule + presentation metadata" {
  match @lsp.lsp_capsule_function_lines("scan_bytes", run_id="doc") {
    None => fail("missing scan_bytes")
    Some(lines) => {
      assert_eq(lines[0], "kind: :lang_contract_capsule")
      assert_true(lines[4].has_prefix("@method"))
      assert_true(lines[lines.length() - 6].has_prefix("@category "))
      assert_true(lines[lines.length() - 5].has_prefix("@func_type "))
      assert_true(lines[lines.length() - 4].has_prefix("@wasi_world "))
      assert_true(lines[lines.length() - 3].has_prefix("@wasm_target "))
      assert_true(lines[lines.length() - 2].has_prefix("@oci_media_type "))
      assert_true(lines[lines.length() - 1].has_prefix("@oci_compliant "))
    }
  }
}
