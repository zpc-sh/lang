///|
/// Integer-ABI host bridge for sdk/wasm slim clients.
///
/// Slot protocol:
///   - Slot 1: primary input (node id, JSON payload, LSP wire bytes, mulsp_id)
///   - Slot 2: secondary input (codex function list CSV)
///   - Out: one output frame/blob per `lm_sdk_drain` / `lm_sdk_codex_mulsp`
///
/// Profile ids:
///   0 = jsonrpc
///   1 = proxy
///   2 = claude
///   3 = codex
///
/// Host mode ids:
///   0 = stub host bridge
///   1 = managed host bridge (configured over lm_sdk_host_* APIs)

///|
let lm_s1 : Array[Byte] = Array::make(65536, b'\x00')

///|
let lm_s1_len : Ref[Int] = { val: 0 }

///|
let lm_s2 : Array[Byte] = Array::make(65536, b'\x00')

///|
let lm_s2_len : Ref[Int] = { val: 0 }

///|
let lm_out : Array[Byte] = Array::make(65536, b'\x00')

///|
let lm_out_len : Ref[Int] = { val: 0 }

///|
let g_profile : Ref[Int] = { val: 0 }

///|
let g_client : Ref[@core.SlimClient?] = { val: None }

///|
let g_pending_out : Array[Array[Byte]] = []

///|
let g_host_mode : Ref[Int] = { val: 0 }

///|
let g_host_name : Ref[String] = { val: "sdk-host" }

///|
let g_host_has_network : Ref[Bool] = { val: false }

///|
let g_host_has_filesystem : Ref[Bool] = { val: false }

///|
let g_host_has_clock : Ref[Bool] = { val: true }

///|
let g_host_has_logging : Ref[Bool] = { val: true }

///|
let g_host_has_crypto : Ref[Bool] = { val: false }

///|
let g_host_now_ms : Ref[Int] = { val: 0 }

///|
let g_host_blob_store : Map[String, Array[Byte]] = {}

///|
let g_host_logs : Array[String] = []

///|
pub fn lm_sdk_put(i : Int, b : Int) -> Unit {
  lm_s1[i] = (b & 0xFF).to_byte()
}

///|
pub fn lm_sdk_len(n : Int) -> Unit {
  lm_s1_len.val = n
}

///|
pub fn lm_sdk_put2(i : Int, b : Int) -> Unit {
  lm_s2[i] = (b & 0xFF).to_byte()
}

///|
pub fn lm_sdk_len2(n : Int) -> Unit {
  lm_s2_len.val = n
}

///|
pub fn lm_sdk_out_len() -> Int {
  lm_out_len.val
}

///|
pub fn lm_sdk_out_get(i : Int) -> Int {
  lm_out[i].to_int() & 0xFF
}

///|
pub fn lm_sdk_profile_set(profile_id : Int) -> Unit {
  g_profile.val = profile_id
}

///|
pub fn lm_sdk_profile_get() -> Int {
  g_profile.val
}

///|
/// Select host mode: 0=stub, 1=managed.
pub fn lm_sdk_host_mode_set(mode : Int) -> Unit {
  g_host_mode.val = mode
}

///|
pub fn lm_sdk_host_mode_get() -> Int {
  g_host_mode.val
}

///|
/// Configure host capabilities for managed mode.
pub fn lm_sdk_host_caps_set(
  has_network : Int,
  has_filesystem : Int,
  has_clock : Int,
  has_logging : Int,
  has_crypto : Int,
) -> Unit {
  g_host_has_network.val = has_network != 0
  g_host_has_filesystem.val = has_filesystem != 0
  g_host_has_clock.val = has_clock != 0
  g_host_has_logging.val = has_logging != 0
  g_host_has_crypto.val = has_crypto != 0
}

///|
/// Set host name from slot2 bytes.
pub fn lm_sdk_host_name_from_slot2() -> Unit {
  g_host_name.val = wasm_slot_to_str(lm_s2, lm_s2_len.val)
}

///|
pub fn lm_sdk_host_now_set(now_ms : Int) -> Unit {
  g_host_now_ms.val = now_ms
}

///|
/// Put blob using slot1 as key and slot2 as data.
pub fn lm_sdk_host_blob_put_slots() -> Int {
  let key = wasm_slot_to_str(lm_s1, lm_s1_len.val)
  if key.length() == 0 {
    return 0
  }
  g_host_blob_store[key] = wasm_slot_slice(lm_s2, lm_s2_len.val)
  1
}

///|
/// Get blob by key in slot1 and copy blob bytes to output.
pub fn lm_sdk_host_blob_get_slot1() -> Int {
  let key = wasm_slot_to_str(lm_s1, lm_s1_len.val)
  match g_host_blob_store.get(key) {
    Some(data) => {
      wasm_copy_to_out(data)
      1
    }
    None => {
      lm_out_len.val = 0
      0
    }
  }
}

///|
/// Return 1 iff blob key in slot1 exists.
pub fn lm_sdk_host_blob_has_slot1() -> Int {
  let key = wasm_slot_to_str(lm_s1, lm_s1_len.val)
  match g_host_blob_store.get(key) {
    Some(_) => 1
    None => 0
  }
}

///|
pub fn lm_sdk_host_log_pending() -> Int {
  g_host_logs.length()
}

///|
/// Drain one managed-host log line to output bytes.
pub fn lm_sdk_host_log_drain() -> Int {
  match g_host_logs {
    [] => {
      lm_out_len.val = 0
      0
    }
    [first, ..rest] => {
      wasm_copy_to_out(wasm_str_to_bytes(first))
      g_host_logs.clear()
      for line in rest {
        g_host_logs.push(line)
      }
      1
    }
  }
}

///|
pub fn lm_sdk_boot() -> Int {
  let node_id_raw = wasm_slot_to_str(lm_s1, lm_s1_len.val)
  let node_id = if node_id_raw.length() > 0 { node_id_raw } else { "sdk-wasm" }
  let flavor = wasm_profile_to_flavor(g_profile.val)
  let host = wasm_make_host_bridge()
  g_client.val = Some(@core.SlimClient::boot(node_id, flavor, host))
  g_pending_out.clear()
  lm_out_len.val = 0
  1
}

///|
/// Persist a checkpoint and place the returned CAS key into output bytes.
pub fn lm_sdk_checkpoint() -> Int {
  match g_client.val {
    Some(client) => {
      let key = client.checkpoint()
      g_client.val = Some(client)
      wasm_copy_to_out(wasm_str_to_bytes(key))
      1
    }
    None => 0
  }
}

///|
pub fn lm_sdk_ready() -> Int {
  match g_client.val {
    Some(_) => 1
    None => 0
  }
}

///|
pub fn lm_sdk_emit() -> Int {
  let json = wasm_slot_to_str(lm_s1, lm_s1_len.val)
  if json.length() == 0 {
    return 0
  }
  match g_client.val {
    Some(client) => {
      client.emit_lsp(json)
      g_client.val = Some(client)
      1
    }
    None => 0
  }
}

///|
/// Execute a self-emitted dual-contract block when it is deploy-ready and
/// mulsp channel capabilities are present.
///
///   slot1 = muon-like contract lines joined by "\n"
///   slot2 = comma-separated codex function names for mulsp channel gate
pub fn lm_sdk_emit_contract() -> Int {
  let contract_block = wasm_slot_to_str(lm_s1, lm_s1_len.val)
  if contract_block.length() == 0 {
    return 0
  }
  if !wasm_contract_block_ready(contract_block) {
    return 0
  }
  let functions = wasm_split_csv(wasm_slot_to_str(lm_s2, lm_s2_len.val))
  let channel_mulsp = @codex_client.mulsp_for_functions(
    "codex-wasm-contract",
    "ratio/codex",
    functions,
  )
  if !wasm_has_codex_connector_channel(channel_mulsp.capability_refs) {
    return 0
  }
  let command_json = @portable_wasi.execute_command_json(
    "lsp.dual.contract.execute",
    contract_block,
  )
  match g_client.val {
    Some(client) => {
      client.emit_lsp(command_json)
      g_client.val = Some(client)
      1
    }
    None => 0
  }
}

///|
/// Preflight dual-contract execution gate.
///
/// Returns bitmask:
///   1 = deploy/cross-repo ready lines present
///   2 = codex connector channel capability present
pub fn lm_sdk_contract_preflight() -> Int {
  let contract_block = wasm_slot_to_str(lm_s1, lm_s1_len.val)
  let ready = contract_block.length() > 0 && wasm_contract_block_ready(contract_block)
  let functions = wasm_split_csv(wasm_slot_to_str(lm_s2, lm_s2_len.val))
  let channel_mulsp = @codex_client.mulsp_for_functions(
    "codex-wasm-contract",
    "ratio/codex",
    functions,
  )
  let has_channel = wasm_has_codex_connector_channel(channel_mulsp.capability_refs)
  @portable_wasi.preflight_bits(ready, has_channel)
}

///|
pub fn lm_sdk_ingest() -> Int {
  let bytes = wasm_slot_slice(lm_s1, lm_s1_len.val)
  match g_client.val {
    Some(client) => {
      client.ingest_lsp(bytes)
      g_client.val = Some(client)
      1
    }
    None => 0
  }
}

///|
pub fn lm_sdk_tick(now_ms : Int) -> Int {
  match g_client.val {
    Some(client) => {
      client.tick(now_ms)
      g_client.val = Some(client)
      1
    }
    None => 0
  }
}

///|
pub fn lm_sdk_flavor() -> Int {
  match g_client.val {
    Some(client) => wasm_flavor_to_int(client.flavor())
    None => -1
  }
}

///|
pub fn lm_sdk_pending_out() -> Int {
  g_pending_out.length()
}

///|
pub fn lm_sdk_drain() -> Int {
  if g_pending_out.length() == 0 {
    match g_client.val {
      Some(client) => {
        let frames = client.drain_output()
        g_client.val = Some(client)
        for frame in frames {
          g_pending_out.push(frame)
        }
      }
      None => ()
    }
  }
  match g_pending_out {
    [] => {
      lm_out_len.val = 0
      0
    }
    [first, ..rest] => {
      wasm_copy_to_out(first)
      g_pending_out.clear()
      for frame in rest {
        g_pending_out.push(frame)
      }
      1
    }
  }
}

///|
/// Build a codex-tailored mulsp from current slots.
///
///   slot1 = mulsp_id
///   slot2 = comma-separated function names
pub fn lm_sdk_codex_mulsp() -> Int {
  let mulsp_id_raw = wasm_slot_to_str(lm_s1, lm_s1_len.val)
  let mulsp_id = if mulsp_id_raw.length() > 0 { mulsp_id_raw } else { "codex-wasm" }
  let fn_csv = wasm_slot_to_str(lm_s2, lm_s2_len.val)
  let functions = wasm_split_csv(fn_csv)
  let state = @codex_client.mulsp_for_functions(mulsp_id, "ratio/codex", functions)
  wasm_copy_to_out(state.to_bytes())
  1
}

///|
fn wasm_profile_to_flavor(profile_id : Int) -> @core.SlimClientFlavor {
  match profile_id {
    1 => @core.Proxy
    2 => @core.ClaudeProcess
    3 => @core.Codex
    _ => @core.Core
  }
}

///|
fn wasm_flavor_to_int(flavor : @core.SlimClientFlavor) -> Int {
  match flavor {
    @core.Core => 0
    @core.Proxy => 1
    @core.ClaudeProcess => 2
    @core.Codex => 3
  }
}

///|
fn wasm_make_host_bridge() -> @node.HostBridge {
  if g_host_mode.val == 0 {
    return @node.HostBridge::stub()
  }
  {
    capabilities: {
      has_network: g_host_has_network.val,
      has_filesystem: g_host_has_filesystem.val,
      has_clock: g_host_has_clock.val,
      has_logging: g_host_has_logging.val,
      has_crypto: g_host_has_crypto.val,
      host_name: g_host_name.val,
    },
    mono_now_ms: fn() -> Int { g_host_now_ms.val },
    log_trace: fn(msg : String) -> Unit { wasm_host_log("trace", msg) },
    log_info: fn(msg : String) -> Unit { wasm_host_log("info", msg) },
    log_warn: fn(msg : String) -> Unit { wasm_host_log("warn", msg) },
    log_error: fn(msg : String) -> Unit { wasm_host_log("error", msg) },
    blob_put: fn(key : String, data : Array[Byte]) -> Bool {
      g_host_blob_store[key] = data
      true
    },
    blob_get: fn(key : String) -> Array[Byte]? { g_host_blob_store.get(key) },
    blob_has: fn(key : String) -> Bool { g_host_blob_store.get(key) is Some(_) },
    net_send: fn(_fd : Int, _data : Array[Byte]) -> Bool { false },
    net_recv: fn(_fd : Int) -> Array[Byte]? { None },
    net_listen: fn(_port : Int) -> Int { -1 },
    net_accept: fn(_fd : Int) -> Int? { None },
    net_connect: fn(_host : String, _port : Int) -> Int? { None },
    crypto_hash: fn(data : Array[Byte]) -> Array[Byte] { wasm_hash_stub(data) },
    crypto_sign: fn(_msg : Array[Byte], _key : Array[Byte]) -> Array[Byte] {
      Array::make(64, b'\x00')
    },
    crypto_verify: fn(
      _msg : Array[Byte],
      _sig : Array[Byte],
      _pubkey : Array[Byte],
    ) -> Bool {
      false
    },
  }
}

///|
fn wasm_host_log(level : String, msg : String) -> Unit {
  if g_host_has_logging.val {
    g_host_logs.push(level + ":" + msg)
  }
}

///|
fn wasm_hash_stub(data : Array[Byte]) -> Array[Byte] {
  let mut h = 0x811C9DC5
  for b in data {
    h = h ^ (b.to_int() & 0xFF)
    h = h * 0x01000193
  }
  [
    ((h >> 24) & 0xFF).to_byte(),
    ((h >> 16) & 0xFF).to_byte(),
    ((h >> 8) & 0xFF).to_byte(),
    (h & 0xFF).to_byte(),
  ]
}

///|
fn wasm_copy_to_out(data : Array[Byte]) -> Unit {
  let n = data.length()
  let cap = lm_out.length()
  let mut i = 0
  while i < n && i < cap {
    lm_out[i] = data[i]
    i = i + 1
  }
  lm_out_len.val = i
}

///|
fn wasm_slot_slice(buf : Array[Byte], len : Int) -> Array[Byte] {
  let out = Array::make(len, b'\x00')
  let mut i = 0
  while i < len {
    out[i] = buf[i]
    i = i + 1
  }
  out
}

///|
fn wasm_slot_to_str(buf : Array[Byte], len : Int) -> String {
  let sb = StringBuilder::new()
  let mut i = 0
  while i < len {
    let b0 = buf[i].to_int()
    if (b0 & 0x80) == 0 {
      sb.write_char(b0.to_char().unwrap())
      i = i + 1
    } else if (b0 & 0xE0) == 0xC0 && i + 1 < len {
      let b1 = buf[i + 1].to_int()
      sb.write_char((((b0 & 0x1F) << 6) | (b1 & 0x3F)).to_char().unwrap())
      i = i + 2
    } else if (b0 & 0xF0) == 0xE0 && i + 2 < len {
      let b1 = buf[i + 1].to_int()
      let b2 = buf[i + 2].to_int()
      sb.write_char(
        (((b0 & 0x0F) << 12) | ((b1 & 0x3F) << 6) | (b2 & 0x3F))
        .to_char()
        .unwrap(),
      )
      i = i + 3
    } else {
      sb.write_char('\u{FFFD}')
      i = i + 1
    }
  }
  sb.to_string()
}

///|
fn wasm_str_to_bytes(s : String) -> Array[Byte] {
  let out : Array[Byte] = []
  for ch in s {
    let cp = ch.to_int()
    if cp < 0x80 {
      out.push(cp.to_byte())
    } else if cp < 0x800 {
      out.push((0xC0 | (cp >> 6)).to_byte())
      out.push((0x80 | (cp & 0x3F)).to_byte())
    } else {
      out.push((0xE0 | (cp >> 12)).to_byte())
      out.push((0x80 | ((cp >> 6) & 0x3F)).to_byte())
      out.push((0x80 | (cp & 0x3F)).to_byte())
    }
  }
  out
}

///|
fn wasm_split_csv(s : String) -> Array[String] {
  let out : Array[String] = []
  if s.length() == 0 {
    return out
  }
  let chars = s.to_array()
  let len = chars.length()
  let mut start = 0
  let mut i = 0
  while i < len {
    if chars[i] == ',' {
      let part = s[start:i].to_owned()
      if part.length() > 0 {
        out.push(part)
      }
      start = i + 1
    }
    i = i + 1
  }
  if start < len {
    let part = s[start:].to_owned()
    if part.length() > 0 {
      out.push(part)
    }
  }
  out
}

///|
fn wasm_contract_block_ready(block : String) -> Bool {
  @portable_wasi.block_has_ready_markers(block)
}

///|
fn wasm_has_codex_connector_channel(capability_refs : Array[String]) -> Bool {
  @portable_wasi.has_required_capability(
    capability_refs,
    @portable_wasi.required_codex_connector_capability(),
  )
}
