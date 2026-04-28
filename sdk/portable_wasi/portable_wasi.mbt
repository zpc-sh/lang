///|
/// Portable WASI/WIT execution pattern helpers.
///
/// This package captures the reusable boundary pattern:
///   1. self-emitted contract block
///   2. capability gate
///   3. deterministic preflight bitmask
///   4. JSON-RPC executeCommand envelope

///|
pub(all) enum ExportSurface {
  Direct
  SlotAbi
} derive(Eq, Debug)

///|
pub fn required_codex_connector_capability() -> String {
  "fn:codex.connector.channel"
}

///|
pub fn preflight_bits(ready : Bool, has_channel : Bool) -> Int {
  let mut code = 0
  if ready {
    code = code + 1
  }
  if has_channel {
    code = code + 2
  }
  code
}

///|
pub fn block_has_ready_markers(block : String) -> Bool {
  let mut deploy_ready = false
  let mut cross_repo_ready = false
  for line in split_lines(block) {
    if line == "@deploy_ready true" {
      deploy_ready = true
    }
    if line == "@cross_repo_ready true" {
      cross_repo_ready = true
    }
  }
  deploy_ready && cross_repo_ready
}

///|
pub fn has_required_capability(
  capability_refs : Array[String],
  required : String,
) -> Bool {
  for cap in capability_refs {
    if cap == required {
      return true
    }
  }
  false
}

///|
pub fn execute_command_json(command : String, arg : String) -> String {
  "{\"jsonrpc\":\"2.0\",\"method\":\"workspace/executeCommand\",\"params\":{\"command\":\"" +
  json_escape(command) +
  "\",\"arguments\":[\"" +
  json_escape(arg) +
  "\"]}}"
}

///|
pub fn split_lines(s : String) -> Array[String] {
  let out : Array[String] = []
  if s.length() == 0 {
    return out
  }
  let chars = s.to_array()
  let len = chars.length()
  let mut start = 0
  let mut i = 0
  while i < len {
    if chars[i] == '\n' {
      out.push(s[start:i].to_owned())
      start = i + 1
    }
    i = i + 1
  }
  if start <= len {
    out.push(s[start:].to_owned())
  }
  out
}

///|
pub fn json_escape(s : String) -> String {
  let out = StringBuilder::new()
  for ch in s {
    if ch == '"' {
      out.write_string("\\\"")
    } else if ch == '\\' {
      out.write_string("\\\\")
    } else if ch == '\n' {
      out.write_string("\\n")
    } else if ch == '\r' {
      out.write_string("\\r")
    } else if ch == '\t' {
      out.write_string("\\t")
    } else {
      out.write_char(ch)
    }
  }
  out.to_string()
}
