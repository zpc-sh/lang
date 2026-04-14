// Movement — what the process is doing, not who it is.
//
// We record categories and sizes, never method names or payload content.
// A process that's doing navigation looks different from one doing edits —
// but we can't say it's Claude specifically, because:
//   (a) the size labels are bucketed
//   (b) timestamps are blurred
//   (c) decoy events are injected
//   (d) multiple processes aggregate into the same void
//
// Movement is derived from two sources:
//   - LSP frame stream (editor ↔ language server traffic)
//   - /proc/<pid>/stat snapshots (CPU ticks, RSS, fd count)
//
// Both are processed through Jitter before entering the void.

/// Broad category of LSP method — loses specificity, keeps signal.
pub(all) enum MethodCategory {
  Navigation    // definition, references, hover, highlight
  Completion    // completion, resolve
  Diagnostic    // publishDiagnostics, diagnostic pull
  Edit          // didChange, didOpen, didClose, didSave, rename, format
  Lifecycle     // initialize, initialized, shutdown, exit, cancel
  Unknown
} derive(Eq, Debug)

impl Show for MethodCategory with output(self, logger) {
  logger.write_string(match self {
    Navigation  => "nav"
    Completion  => "cmp"
    Diagnostic  => "diag"
    Edit        => "edit"
    Lifecycle   => "life"
    Unknown     => "unk"
  })
}

/// Assign a category from a raw LSP method string.
/// Called on the pass-through copy — never stored.
pub fn categorize(lsp_method : String) -> MethodCategory {
  if lsp_method == "initialize"  || lsp_method == "initialized" ||
     lsp_method == "shutdown"    || lsp_method == "exit"        ||
     lsp_method == "$/cancelRequest" {
    Lifecycle
  } else if lsp_method.has_prefix("textDocument/definition")       ||
            lsp_method.has_prefix("textDocument/references")       ||
            lsp_method.has_prefix("textDocument/hover")            ||
            lsp_method.has_prefix("textDocument/documentHighlight")||
            lsp_method.has_prefix("textDocument/typeDefinition")   ||
            lsp_method.has_prefix("textDocument/implementation") {
    Navigation
  } else if lsp_method.has_prefix("textDocument/completion") ||
            lsp_method.has_prefix("completionItem/") {
    Completion
  } else if lsp_method.has_prefix("textDocument/diagnostic")    ||
            lsp_method == "textDocument/publishDiagnostics"     ||
            lsp_method == "$/publishDiagnostics" {
    Diagnostic
  } else if lsp_method.has_prefix("textDocument/did") ||
            lsp_method.has_prefix("textDocument/rename") ||
            lsp_method.has_prefix("textDocument/format") ||
            lsp_method.has_prefix("workspace/") {
    Edit
  } else {
    Unknown
  }
}

// ---------------------------------------------------------------------------
// Batch accumulation — we don't emit one observation per frame.
// ---------------------------------------------------------------------------

/// One sealed movement batch, ready to write into the void.
/// Contains no raw content, no exact sizes, no precise timestamps.
pub(all) struct MovementBatch {
  frame_count   : Int    // total frames in this batch
  size_sum      : Int    // sum of bucketed sizes (not exact total)
  nav_count     : Int
  cmp_count     : Int
  diag_count    : Int
  edit_count    : Int
  life_count    : Int
  unk_count     : Int
  jittered_ms   : Int    // blurred wall-clock time of batch seal
  is_decoy      : Bool   // true if this batch was synthetically injected
} derive(Debug)

/// Mutable accumulator for one batch.
pub(all) struct BatchAccum {
  mut frame_count : Int
  mut size_sum    : Int
  mut nav_count   : Int
  mut cmp_count   : Int
  mut diag_count  : Int
  mut edit_count  : Int
  mut life_count  : Int
  mut unk_count   : Int
} derive(Debug)

pub fn BatchAccum::new() -> BatchAccum {
  {
    frame_count: 0, size_sum: 0,
    nav_count: 0, cmp_count: 0,
    diag_count: 0, edit_count: 0,
    life_count: 0, unk_count: 0,
  }
}

pub fn BatchAccum::is_empty(self : BatchAccum) -> Bool {
  self.frame_count == 0
}

/// Record one observed frame (body size + method category).
/// Size is bucketed immediately — raw size is not retained.
pub fn BatchAccum::observe(
  self : BatchAccum,
  raw_size : Int,
  cat      : MethodCategory
) -> Unit {
  self.frame_count = self.frame_count + 1
  self.size_sum    = self.size_sum + bucket(raw_size, 512)
  match cat {
    Navigation => self.nav_count  = self.nav_count  + 1
    Completion => self.cmp_count  = self.cmp_count  + 1
    Diagnostic => self.diag_count = self.diag_count + 1
    Edit       => self.edit_count = self.edit_count + 1
    Lifecycle  => self.life_count = self.life_count + 1
    Unknown    => self.unk_count  = self.unk_count  + 1
  }
}

/// Seal the accumulator into a MovementBatch and reset.
pub fn BatchAccum::seal(
  self        : BatchAccum,
  jittered_ms : Int,
  is_decoy    : Bool
) -> MovementBatch {
  let b : MovementBatch = {
    frame_count: self.frame_count,
    size_sum:    bucket(self.size_sum, 512),
    nav_count:   self.nav_count,
    cmp_count:   self.cmp_count,
    diag_count:  self.diag_count,
    edit_count:  self.edit_count,
    life_count:  self.life_count,
    unk_count:   self.unk_count,
    jittered_ms,
    is_decoy,
  }
  // Reset accumulator fields.
  self.frame_count = 0
  self.size_sum    = 0
  self.nav_count   = 0
  self.cmp_count   = 0
  self.diag_count  = 0
  self.edit_count  = 0
  self.life_count  = 0
  self.unk_count   = 0
  b
}

// ---------------------------------------------------------------------------
// /proc snapshot types — for process-level observation.
// Actual /proc reading is done by the host via extern.
// ---------------------------------------------------------------------------

/// One snapshot of a process from /proc/<pid>/stat + /proc/<pid>/status.
/// Fields are taken as-is from proc — jitter is applied at the observer level.
pub(all) struct ProcSnapshot {
  pid        : Int
  comm       : String   // process name from /proc/<pid>/comm (truncated to 15 chars by kernel)
  state      : Char     // R S D Z T I
  utime      : Int      // user-mode CPU ticks
  stime      : Int      // kernel-mode CPU ticks
  rss_pages  : Int      // resident set size in pages
  fd_count   : Int      // count of entries in /proc/<pid>/fd/
  sampled_at : Int      // raw wall-clock ms (before jitter)
} derive(Debug)

/// Delta between two consecutive snapshots.
pub(all) struct ProcDelta {
  cpu_ticks    : Int   // utime+stime delta (activity indicator)
  rss_delta    : Int   // pages delta (positive = growing)
  fd_delta     : Int   // fd count delta
  elapsed_ms   : Int   // raw elapsed time (before jitter)
  was_active   : Bool  // cpu_ticks > 0 || rss_delta != 0
}

pub fn diff_snapshots(prev : ProcSnapshot, cur : ProcSnapshot) -> ProcDelta {
  let cpu  = (cur.utime + cur.stime) - (prev.utime + prev.stime)
  let rss  = cur.rss_pages - prev.rss_pages
  let fds  = cur.fd_count  - prev.fd_count
  let ela  = cur.sampled_at - prev.sampled_at
  {
    cpu_ticks:  if cpu > 0 { cpu } else { 0 },
    rss_delta:  rss,
    fd_delta:   fds,
    elapsed_ms: if ela > 0 { ela } else { 0 },
    was_active: cpu > 0 || rss != 0,
  }
}
