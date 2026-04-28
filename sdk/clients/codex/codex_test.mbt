///|
test "codex mulsp plan keeps exact function capability set" {
  let m = mulsp_for_functions(
    "codex-1",
    "ratio/codex",
    ["edit.apply", "build.emit", "edit.apply", ""],
  )
  assert_eq(m.capability_refs.length(), 2)
  assert_eq(m.capability_refs[0], "fn:edit.apply")
  assert_eq(m.capability_refs[1], "fn:build.emit")
  assert_eq(m.handler, "codex")
}
