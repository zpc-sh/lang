// Observer — the claude_process accumulator.
//
// ClaudeObserver is the stateful core. It:
//   1. Receives LSP frames (or proc snapshots) from the host
//   2. Applies jitter immediately — raw data is never stored
//   3. Accumulates movement into batches
//   4. Flushes batches into the Void when threshold is reached
//   5. Injects synthetic decoy movement with low probability
//
// Host integration:
//   The host (Elixir/mulsp, shell/WASI wrapper, or muyata) calls:
//     - observe_frame(body_bytes, now_ms) for each LSP frame
//     - observe_proc(snapshot) for each /proc poll
//     - maybe_flush(now_ms) periodically (e.g. every 5 seconds)
//   And reads:
//     - void_snapshot() to get the current void state
//     - to_bytes() / from_bytes() for persistence across restarts
//
// The observer is deliberately NOT a transparent proxy at this layer.
// Pass-through of raw bytes is the host's responsibility. The observer
// only sees sizes and method categories, never payload content.

///|
/// Configuration for the observer.
pub(all) struct ObserverConfig {
  node_id : String // identity of this observer instance
  batch_size : Int // flush void after this many frames
  time_jitter_ms : Int // ± ms blur on all timestamps
  decoy_rate : Int // inject synthetic event 1-in-N flushes (0 = off)
  proc_sample_ms : Int // desired /proc poll interval (hint for host)
} derive(Debug)

///|
pub fn ObserverConfig::default(node_id : String) -> ObserverConfig {
  {
    node_id,
    batch_size: 32, // flush every 32 frames
    time_jitter_ms: 200, // ±200ms temporal blur
    decoy_rate: 7, // ~14% of flushes emit a decoy batch too
    proc_sample_ms: 2000, // poll /proc every ~2s
  }
}

///|
/// The observer state. Immutable at the top level — each observe_* call
/// returns a new ClaudeObserver. Allows pure functional composition.
pub(all) struct ClaudeObserver {
  config : ObserverConfig
  accumulator : @void.Void
  accum : BatchAccum
  jitter : Jitter
  frames_seen : Int // total frames since creation
  flushes : Int // total void flushes
  last_proc : ProcSnapshot?
} derive(Debug)

///|
pub fn ClaudeObserver::new(config : ObserverConfig) -> ClaudeObserver {
  let j = Jitter::from_str(config.node_id)
  {
    config,
    accumulator: @void.Void::new(config.node_id),
    accum: BatchAccum::new(),
    jitter: j,
    frames_seen: 0,
    flushes: 0,
    last_proc: None,
  }
}

// ---------------------------------------------------------------------------
// LSP frame observation
// ---------------------------------------------------------------------------

///|
/// Observe one LSP frame: record its (bucketed) size and method category.
/// The frame body bytes are used only to parse the method — never stored.
///
/// Returns the updated observer. If the batch threshold is reached, the
/// batch is flushed into the void automatically.
pub fn ClaudeObserver::observe_frame(
  self : ClaudeObserver,
  body : Array[Byte],
  now_ms : Int,
) -> ClaudeObserver {
  // Parse just enough to get the method category.
  let msg = @lsp.parse_frame({ content_length: body.length(), body })
  let cat = match msg.lsp_method {
    Some(m) => categorize(m)
    None => Unknown
  }
  self.accum.observe(body.length(), cat)
  let frames = self.frames_seen + 1
  // Track bytes in the void (jittered byte count).
  let jittered_n = bucket(body.length(), 512)
  let v1 = self.accumulator.observe_bytes(jittered_n)
  // Attend to the method category anchor.
  let cat_name = match cat {
    Navigation => "nav"
    Completion => "cmp"
    Diagnostic => "diag"
    Edit => "edit"
    Lifecycle => "life"
    Unknown => "unk"
  }
  let v2 = v1.attend(cat_name)
  // Also attend to size label.
  let v3 = v2.attend(size_label(body.length()))
  let obs1 = { ..self, accumulator: v3, frames_seen: frames }
  // Auto-flush if batch is full.
  if frames % obs1.config.batch_size == 0 {
    obs1.flush(now_ms)
  } else {
    obs1
  }
}

// ---------------------------------------------------------------------------
// /proc observation
// ---------------------------------------------------------------------------

///|
/// Observe a /proc snapshot. Returns updated observer.
/// Jitter is applied to the timestamp; raw CPU/RSS values are bucketed.
pub fn ClaudeObserver::observe_proc(
  self : ClaudeObserver,
  snap : ProcSnapshot,
) -> ClaudeObserver {
  let j = self.jitter
  let blurred_ms = j.blur_time(snap.sampled_at, self.config.time_jitter_ms)
  let v1 = match self.last_proc {
    None => self.accumulator
    Some(prev) => {
      let delta = diff_snapshots(prev, snap)
      let mut v = self.accumulator
      if delta.was_active {
        // Mark activity — bucketed CPU ticks as a size-like measure.
        v = v.observe_bytes(bucket(delta.cpu_ticks * 4096, 512))
        v = v.attend("proc-active")
      }
      if delta.fd_delta > 0 {
        v = v.attend("proc-fd-open")
      } else if delta.fd_delta < 0 {
        v = v.attend("proc-fd-close")
      }
      if delta.rss_delta > 0 {
        v = v.attend("proc-grow")
      }
      // Decoy: occasionally fake a "quiet" signal even when active.
      if j.coin(5) {
        v = v.attend("proc-quiet")
      }
      v = v.observe_bytes(blurred_ms) // time as a byte count (noise)
      v
    }
  }
  { ..self, accumulator: v1, last_proc: Some(snap) }
}

// ---------------------------------------------------------------------------
// Flush — seal batch into void, optionally inject decoy
// ---------------------------------------------------------------------------

///|
/// Flush the current batch into the void and optionally emit a decoy.
/// Called automatically from observe_frame, or explicitly by the host.
pub fn ClaudeObserver::flush(
  self : ClaudeObserver,
  now_ms : Int,
) -> ClaudeObserver {
  let j = self.jitter
  let blurred = j.blur_time(now_ms, self.config.time_jitter_ms)
  let mut v = self.accumulator
  // Seal and apply the real batch if non-empty.
  if !self.accum.is_empty() {
    let batch = self.accum.seal(blurred, false)
    v = apply_batch(v, batch)
  }
  // Optionally inject a decoy batch.
  let inject = self.config.decoy_rate > 0 && j.coin(self.config.decoy_rate)
  if inject {
    let decoy = make_decoy_batch(j, blurred)
    v = apply_batch(v, decoy)
    v = v.attend("decoy")
  }
  v = v.tick()
  { ..self, accumulator: v, flushes: self.flushes + 1 }
}

///|
/// Explicit flush — host calls this on a timer (e.g. every 5 seconds).
pub fn ClaudeObserver::maybe_flush(
  self : ClaudeObserver,
  now_ms : Int,
) -> ClaudeObserver {
  self.flush(now_ms)
}

///|
/// The current void — call this to read accumulated state.
pub fn ClaudeObserver::void_snapshot(self : ClaudeObserver) -> @void.Void {
  self.accumulator
}

// ---------------------------------------------------------------------------
// Persistence
// ---------------------------------------------------------------------------

///|
/// Serialize observer state to bytes for .cog section or disk.
/// Only the void and config node_id survive — jitter re-seeds from node_id.
pub fn ClaudeObserver::to_bytes(self : ClaudeObserver) -> Array[Byte] {
  self.accumulator.to_bytes()
}

///|
/// Restore observer from persisted void bytes with a new config.
pub fn ClaudeObserver::from_bytes(
  data : Array[Byte],
  config : ObserverConfig,
) -> ClaudeObserver? {
  match @void.Void::from_bytes(data) {
    None => None
    Some(v) => {
      let j = Jitter::from_str(config.node_id)
      Some({
        config,
        accumulator: v,
        accum: BatchAccum::new(),
        jitter: j,
        frames_seen: 0,
        flushes: 0,
        last_proc: None,
      })
    }
  }
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

///|
fn apply_batch(v : @void.Void, batch : MovementBatch) -> @void.Void {
  let mut out = v
  if batch.frame_count > 0 {
    out = out.observe_bytes(batch.size_sum)
  }
  // Attend once per category count (weight accumulates naturally).
  let mut i = 0
  while i < batch.nav_count {
    out = out.attend("nav")
    i = i + 1
  }
  i = 0
  while i < batch.cmp_count {
    out = out.attend("cmp")
    i = i + 1
  }
  i = 0
  while i < batch.diag_count {
    out = out.attend("diag")
    i = i + 1
  }
  i = 0
  while i < batch.edit_count {
    out = out.attend("edit")
    i = i + 1
  }
  i = 0
  while i < batch.life_count {
    out = out.attend("life")
    i = i + 1
  }
  out
}

// Synthesize a plausible but fake movement batch.

///|
fn make_decoy_batch(j : Jitter, jittered_ms : Int) -> MovementBatch {
  {
    frame_count: (j.next() & 0x1F) + 1,
    size_sum: bucket((j.next() & 0xFF) * 512, 512),
    nav_count: j.next() & 0x07,
    cmp_count: j.next() & 0x03,
    diag_count: j.next() & 0x01,
    edit_count: j.next() & 0x03,
    life_count: 0,
    unk_count: j.next() & 0x01,
    jittered_ms,
    is_decoy: true,
  }
}
