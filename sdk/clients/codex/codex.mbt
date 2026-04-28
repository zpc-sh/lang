///|
/// Slim SDK profile for Codex-specific runtime behavior.

///|
pub(all) struct CodexMulspPlan {
  execution_surface : String
  handler : String
  function_caps : Array[String]
} derive(Debug)

///|
fn codex_normalize_functions(functions : Array[String]) -> Array[String] {
  let out : Array[String] = []
  for fn_name in functions {
    if fn_name.length() == 0 {
      continue
    }
    let mut seen = false
    for existing in out {
      if existing == fn_name {
        seen = true
        break
      }
    }
    if !seen {
      out.push(fn_name)
    }
  }
  out
}

///|
fn codex_fn_capability(fn_name : String) -> String {
  "fn:" + fn_name
}

///|
/// Build a codex mulsp plan from exactly the function set needed now.
pub fn CodexMulspPlan::for_functions(functions : Array[String]) -> CodexMulspPlan {
  let normalized = codex_normalize_functions(functions)
  let function_caps : Array[String] = []
  for fn_name in normalized {
    function_caps.push(codex_fn_capability(fn_name))
  }
  {
    execution_surface: "wasm-gc",
    handler: "codex",
    function_caps,
  }
}

///|
/// Apply this plan to build a mulsp state with only the requested function caps.
pub fn CodexMulspPlan::build_mulsp(
  self : CodexMulspPlan,
  mulsp_id : String,
  ratio_loci : String,
) -> @mulsp.MulspState {
  let mut state = @mulsp.MulspState::new(
    mulsp_id,
    ratio_loci,
    self.execution_surface,
    self.handler,
  )
  for cap in self.function_caps {
    state = state.add_capability(cap)
  }
  state
}

///|
/// Convenience boot for codex slim client profile.
pub fn boot(node_id : String, host : @node.HostBridge) -> @core.SlimClient {
  @core.SlimClient::boot(node_id, @core.Codex, host)
}

///|
/// Build a codex mulsp state directly from a function list.
pub fn mulsp_for_functions(
  mulsp_id : String,
  ratio_loci : String,
  functions : Array[String],
) -> @mulsp.MulspState {
  CodexMulspPlan::for_functions(functions).build_mulsp(mulsp_id, ratio_loci)
}
