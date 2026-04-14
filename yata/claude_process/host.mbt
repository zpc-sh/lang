// Host bridge — lm_* integer-ABI exports for Elixir/wasmex integration.
//
// Integration pattern (mirrors merkin's bridge — same protocol):
//
//   1. Write frame body: lm_cp_put(i, byte) × N, then lm_cp_len(N)
//   2. Observe the frame: lm_cp_observe(now_ms)
//   3. Observe a proc snapshot: format line into slot 1, lm_cp_proc(now_ms)
//   4. Flush on timer: lm_cp_flush(now_ms)
//   5. Read void state: lm_cp_void_bytes() → lm_cp_out_len() + lm_cp_out_get(i)
//   6. Read quick stats: lm_cp_epoch(), lm_cp_frames()
//
// Proc line format (written by Elixir host, read here):
//   "<pid>|<comm>|<state>|<utime>|<stime>|<rss_pages>|<fd_count>"
//
// All module-level mutable state uses Ref[Int] (MoonBit constraint:
// `let mut` is only valid in is-main packages, not library packages).

// ---------------------------------------------------------------------------
// Slot 1 — input bytes from host (frame body or proc line)
// ---------------------------------------------------------------------------

///|
let lm_s1 : Array[Byte] = Array::make(65536, b'\x00')

///|
let lm_s1_len : Ref[Int] = { val: 0 }

///|
let lm_out : Array[Byte] = Array::make(65536, b'\x00')

///|
let lm_out_len : Ref[Int] = { val: 0 }

///|
/// Write one byte at position i into slot 1.
pub fn lm_cp_put(i : Int, b : Int) -> Unit {
  lm_s1[i] = (b & 0xFF).to_byte()
}

///|
/// Set the byte count for slot 1.
pub fn lm_cp_len(n : Int) -> Unit {
  lm_s1_len.val = n
}

///|
/// Read the length of the output buffer.
pub fn lm_cp_out_len() -> Int {
  lm_out_len.val
}

///|
/// Read one byte from the output buffer.
pub fn lm_cp_out_get(i : Int) -> Int {
  lm_out[i].to_int() & 0xFF
}

// ---------------------------------------------------------------------------
// Global state — Ref[Int] for mutables, Array for byte buffers
// ---------------------------------------------------------------------------

///|
let g_jitter : Ref[Int] = { val: 0x5DEECE66 }

///|
let g_batch_frames : Ref[Int] = { val: 0 }

///|
let g_batch_size : Ref[Int] = { val: 0 }

///|
let g_batch_nav : Ref[Int] = { val: 0 }

///|
let g_batch_cmp : Ref[Int] = { val: 0 }

///|
let g_batch_diag : Ref[Int] = { val: 0 }

///|
let g_batch_edit : Ref[Int] = { val: 0 }

///|
let g_batch_life : Ref[Int] = { val: 0 }

///|
let g_frames_seen : Ref[Int] = { val: 0 }

///|
let g_flushes : Ref[Int] = { val: 0 }

///|
let g_batch_thresh : Ref[Int] = { val: 32 }

///|
let g_jitter_ms : Ref[Int] = { val: 200 }

///|
let g_decoy_rate : Ref[Int] = { val: 7 }

// Void — serialized as bytes

///|
let g_void_state : Array[Byte] = Array::make(65536, b'\x00')

///|
let g_void_len : Ref[Int] = { val: 0 }

// Node id — stored as bytes

///|
let g_node_id : Array[Byte] = Array::make(256, b'\x00')

///|
let g_node_id_len : Ref[Int] = { val: 0 }

// Last proc snapshot

///|
let g_proc_pid : Ref[Int] = { val: -1 }

///|
let g_proc_utime : Ref[Int] = { val: 0 }

///|
let g_proc_stime : Ref[Int] = { val: 0 }

///|
let g_proc_rss : Ref[Int] = { val: 0 }

///|
let g_proc_fds : Ref[Int] = { val: 0 }

// ---------------------------------------------------------------------------
// lm_* API
// ---------------------------------------------------------------------------

///|
/// Initialize with a node_id from slot 1.
///  Seeds jitter from the node_id. Call once before first observe.
pub fn lm_cp_init() -> Unit {
  let n = if lm_s1_len.val < g_node_id.length() {
    lm_s1_len.val
  } else {
    g_node_id.length() - 1
  }
  let mut i = 0
  while i < n {
    g_node_id[i] = lm_s1[i]
    i = i + 1
  }
  g_node_id_len.val = n
  // FNV-1a seed from node_id bytes.
  let mut h = 0x811C9DC5
  i = 0
  while i < n {
    h = h ^ lm_s1[i].to_int()
    h = h * 0x01000193
    i = i + 1
  }
  g_jitter.val = h
  // Reset counters.
  g_frames_seen.val = 0
  g_flushes.val = 0
  g_batch_frames.val = 0
  g_batch_size.val = 0
  g_batch_nav.val = 0
  g_batch_cmp.val = 0
  g_batch_diag.val = 0
  g_batch_edit.val = 0
  g_batch_life.val = 0
}

///|
/// Configure thresholds. Call after lm_cp_init if needed.
pub fn lm_cp_configure(
  batch_thresh : Int,
  jitter_ms : Int,
  decoy_rate : Int,
) -> Unit {
  if batch_thresh > 0 {
    g_batch_thresh.val = batch_thresh
  }
  if jitter_ms >= 0 {
    g_jitter_ms.val = jitter_ms
  }
  if decoy_rate >= 0 {
    g_decoy_rate.val = decoy_rate
  }
}

///|
/// Observe an LSP frame: slot 1 = raw frame body. now_ms = host clock.
pub fn lm_cp_observe(now_ms : Int) -> Unit {
  let body_len = lm_s1_len.val
  let body = cp_slot_slice(lm_s1, body_len)
  let msg = @lsp.parse_frame({ content_length: body_len, body })
  let cat = match msg.lsp_method {
    Some(m) => categorize(m)
    None => Unknown
  }
  g_batch_frames.val = g_batch_frames.val + 1
  g_batch_size.val = g_batch_size.val + bucket(body_len, 512)
  match cat {
    Navigation => g_batch_nav.val = g_batch_nav.val + 1
    Completion => g_batch_cmp.val = g_batch_cmp.val + 1
    Diagnostic => g_batch_diag.val = g_batch_diag.val + 1
    Edit => g_batch_edit.val = g_batch_edit.val + 1
    Lifecycle => g_batch_life.val = g_batch_life.val + 1
    Unknown => ()
  }
  g_frames_seen.val = g_frames_seen.val + 1
  if g_frames_seen.val % g_batch_thresh.val == 0 {
    do_flush(now_ms)
  }
}

///|
/// Observe a /proc snapshot: slot 1 = pipe-delimited proc line.
///  Format: "<pid>|<comm>|<state>|<utime>|<stime>|<rss_pages>|<fd_count>"
pub fn lm_cp_proc(now_ms : Int) -> Unit {
  let line = cp_slot_to_str(lm_s1, lm_s1_len.val)
  let parts = cp_str_split(line, '|')
  if parts.length() < 7 {
    return
  }
  let pid = cp_str_to_int(parts[0])
  let utime = cp_str_to_int(parts[3])
  let stime = cp_str_to_int(parts[4])
  let rss = cp_str_to_int(parts[5])
  let fds = cp_str_to_int(parts[6])
  if pid < 0 {
    return
  }
  let mut v = cp_load_void()
  if g_proc_pid.val == pid {
    let cpu = utime + stime - (g_proc_utime.val + g_proc_stime.val)
    let rss_d = rss - g_proc_rss.val
    let fd_d = fds - g_proc_fds.val
    let _ = now_ms
    if cpu > 0 {
      v = v.observe_bytes(bucket(cpu * 4096, 512))
      v = v.attend("proc-active")
    }
    if fd_d > 0 {
      v = v.attend("proc-fd-open")
    }
    if fd_d < 0 {
      v = v.attend("proc-fd-close")
    }
    if rss_d > 0 {
      v = v.attend("proc-grow")
    }
    if cp_jitter_coin(5) {
      v = v.attend("proc-quiet")
    }
  }
  cp_save_void(v)
  g_proc_pid.val = pid
  g_proc_utime.val = utime
  g_proc_stime.val = stime
  g_proc_rss.val = rss
  g_proc_fds.val = fds
}

///|
/// Flush the current batch into the void. Call on a timer (e.g. every 5s).
pub fn lm_cp_flush(now_ms : Int) -> Unit {
  do_flush(now_ms)
}

///|
/// Serialize current void state into output buffer.
pub fn lm_cp_void_bytes() -> Unit {
  let data = cp_load_void().to_bytes()
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
/// Current epoch from the void.
pub fn lm_cp_epoch() -> Int {
  cp_load_void().epoch
}

///|
/// Total frames observed since init.
pub fn lm_cp_frames() -> Int {
  g_frames_seen.val
}

///|
/// Total batch flushes since init.
pub fn lm_cp_flushes() -> Int {
  g_flushes.val
}

// ---------------------------------------------------------------------------
// Private — void persistence
// ---------------------------------------------------------------------------

///|
fn cp_load_void() -> @void.Void {
  if g_void_len.val == 0 {
    let id = cp_slot_to_str(g_node_id, g_node_id_len.val)
    let node_id = if id.length() > 0 { id } else { "claude_process" }
    @void.Void::new(node_id)
  } else {
    let data = cp_slot_slice(g_void_state, g_void_len.val)
    match @void.Void::from_bytes(data) {
      Some(v) => v
      None => @void.Void::new("claude_process")
    }
  }
}

///|
fn cp_save_void(v : @void.Void) -> Unit {
  let data = v.to_bytes()
  let n = data.length()
  let cap = g_void_state.length()
  let mut i = 0
  while i < n && i < cap {
    g_void_state[i] = data[i]
    i = i + 1
  }
  g_void_len.val = i
}

// ---------------------------------------------------------------------------
// Private — flush
// ---------------------------------------------------------------------------

///|
fn do_flush(now_ms : Int) -> Unit {
  let _ = now_ms // timing is implicit via jitter
  let mut v = cp_load_void()
  if g_batch_frames.val > 0 {
    v = v.observe_bytes(bucket(g_batch_size.val, 512))
    let mut i = 0
    while i < g_batch_nav.val {
      v = v.attend("nav")
      i = i + 1
    }
    i = 0
    while i < g_batch_cmp.val {
      v = v.attend("cmp")
      i = i + 1
    }
    i = 0
    while i < g_batch_diag.val {
      v = v.attend("diag")
      i = i + 1
    }
    i = 0
    while i < g_batch_edit.val {
      v = v.attend("edit")
      i = i + 1
    }
    i = 0
    while i < g_batch_life.val {
      v = v.attend("life")
      i = i + 1
    }
  }
  g_batch_frames.val = 0
  g_batch_size.val = 0
  g_batch_nav.val = 0
  g_batch_cmp.val = 0
  g_batch_diag.val = 0
  g_batch_edit.val = 0
  g_batch_life.val = 0
  if g_decoy_rate.val > 0 && cp_jitter_coin(g_decoy_rate.val) {
    let decoy_size = bucket((cp_jitter_next() & 0xFF) * 512, 512)
    v = v.observe_bytes(decoy_size)
    v = v.attend("decoy")
  }
  v = v.observe_session()
  v = v.tick()
  cp_save_void(v)
  g_flushes.val = g_flushes.val + 1
}

// ---------------------------------------------------------------------------
// Private — jitter
// ---------------------------------------------------------------------------

///|
fn cp_jitter_next() -> Int {
  g_jitter.val = g_jitter.val * 1664525 + 1013904223
  (g_jitter.val >> 16) & 0xFFFF
}

///|
fn cp_jitter_coin(one_in_n : Int) -> Bool {
  if one_in_n <= 0 {
    return false
  }
  cp_jitter_next() < 65536 / one_in_n
}

// ---------------------------------------------------------------------------
// Private — string/byte utilities
// ---------------------------------------------------------------------------

///|
fn cp_slot_to_str(buf : Array[Byte], len : Int) -> String {
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
fn cp_slot_slice(buf : Array[Byte], len : Int) -> Array[Byte] {
  let out = Array::make(len, b'\x00')
  let mut i = 0
  while i < len {
    out[i] = buf[i]
    i = i + 1
  }
  out
}

///|
fn cp_str_split(s : String, delim : Char) -> Array[String] {
  let out : Array[String] = []
  let chars = s.to_array()
  let len = chars.length()
  let mut start = 0
  let mut i = 0
  while i < len {
    if chars[i] == delim {
      out.push(s[start:i].to_string())
      start = i + 1
    }
    i = i + 1
  }
  out.push(s[start:].to_string())
  out
}

///|
fn cp_str_to_int(s : String) -> Int {
  let mut n = 0
  let chars = s.to_array()
  let len = chars.length()
  let mut i = 0
  while i < len && (chars[i] == ' ' || chars[i] == '\t') {
    i = i + 1
  }
  while i < len {
    let cp = chars[i].to_int()
    if cp >= 48 && cp <= 57 {
      n = n * 10 + (cp - 48)
      i = i + 1
    } else {
      break
    }
  }
  n
}
