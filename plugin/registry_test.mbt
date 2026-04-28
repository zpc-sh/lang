///|
test "procsi is reserved core capsule and non-clobber by default register" {
  let reg = PluginRegistry::new()
  let abi : PluginAbi = {
    has_init: true,
    has_handle: true,
    has_query: false,
    has_tick: false,
    has_dispose: false,
  }

  let idx1 = reg.register(
    "procsi-v1",
    "procsi",
    "cas://procsi-v1",
    abi,
    [@node.PluginInvoke],
  )
  assert_eq(idx1, 0)
  assert_eq(reg.count(), 1)

  match reg.find_by_name("procsi") {
    Some(p) => {
      assert_true(p.is_core_capsule)
      assert_true(p.wasi_enabled)
      assert_eq(p.replace_generation, 0)
      assert_true(p.procsi_tier == Some("core-capsule"))
    }
    None => fail("expected procsi plugin")
  }

  // Different cas_key should not clobber existing procsi unless replace handler
  let idx2 = reg.register(
    "procsi-v2",
    "procsi",
    "cas://procsi-v2",
    abi,
    [@node.PluginInvoke],
  )
  assert_eq(idx2, 0)
  assert_eq(reg.count(), 1)
}

///|
test "procsi explicit handler effect replacement rotates generation" {
  let reg = PluginRegistry::new()
  let abi : PluginAbi = {
    has_init: true,
    has_handle: true,
    has_query: false,
    has_tick: false,
    has_dispose: false,
  }

  let _ = reg.register(
    "procsi-v1",
    "procsi",
    "cas://procsi-v1",
    abi,
    [@node.PluginInvoke],
  )
  let idx = reg.replace_core_procsi_wasi(
    "procsi-v2",
    "cas://procsi-v2",
    abi,
    [@node.PluginInvoke, @node.Tick],
    "effect://handler/procsi-replace/1",
  )
  assert_eq(idx, 1)
  assert_eq(reg.count(), 2)

  match reg.find_by_name("procsi") {
    Some(p) => {
      assert_eq(p.id, "procsi-v1")
      // find_by_name returns first registration; ensure old is unloaded
      assert_true(p.state == Unloaded)
    }
    None => fail("expected old procsi plugin")
  }

  match reg.find("procsi-v2") {
    Some(p2) => {
      assert_true(p2.is_core_capsule)
      assert_true(p2.wasi_enabled)
      assert_eq(p2.replace_generation, 1)
      assert_true(p2.handler_effect_ref == Some("effect://handler/procsi-replace/1"))
      assert_true(p2.procsi_tier == Some("core-capsule"))
    }
    None => fail("expected new procsi plugin")
  }
}
