// Jitter — temporal and spatial noise to prevent process identification.
//
// The observer accumulates real signals but never stores them precisely.
// Three noise layers:
//
//   1. Time blur  — observation timestamps drift ±range_ms from truth.
//   2. Size bucket — payload sizes rounded to bucket boundaries.
//      No exact byte count is ever recorded.
//   3. Decoy injection — with low probability, a synthetic movement
//      signal is emitted regardless of real activity. This makes
//      traffic analysis a guessing game.
//
// The LCG is seeded from the observer's node_id hash so different
// deployments produce different noise patterns that still aggregate
// correctly in the void.

/// Pseudorandom jitter source. Deterministic per seed — not cryptographic.
/// Suitable for privacy noise, not security.
pub(all) struct Jitter {
  mut state : Int
} derive(Debug)

pub fn Jitter::new(seed : Int) -> Jitter {
  // Mix the seed so a seed of 0 doesn't start at 0.
  let s = seed ^ 0x5DEECE66
  { state: s }
}

/// Seed from a string (node_id, etc.).
pub fn Jitter::from_str(s : String) -> Jitter {
  let mut h = 0x811C9DC5  // FNV-1a offset basis
  for ch in s {
    h = h ^ ch.to_int()
    h = h * 0x01000193   // FNV prime
  }
  Jitter::new(h)
}

/// Advance LCG, return unsigned value in [0, 65535].
fn Jitter::next(self : Jitter) -> Int {
  // Knuth multiplicative congruential — full period over 2^32.
  self.state = self.state * 1664525 + 1013904223
  (self.state >> 16) & 0xFFFF
}

/// Time offset in [-range_ms, +range_ms] ms.
pub fn Jitter::time_offset(self : Jitter, range_ms : Int) -> Int {
  if range_ms <= 0 { return 0 }
  let n = self.next()                        // 0..65535
  let span = 2 * range_ms + 1               // total range
  let scaled = (n * span) >> 16             // 0..span-1
  scaled - range_ms                         // -range_ms..+range_ms
}

/// Add jitter to a timestamp (ms), clamped to [0, ∞).
pub fn Jitter::blur_time(self : Jitter, t_ms : Int, range_ms : Int) -> Int {
  let offset = self.time_offset(range_ms)
  let jittered = t_ms + offset
  if jittered < 0 { 0 } else { jittered }
}

/// True with probability ≈ 1/n (for n > 0). Used for decoy injection.
pub fn Jitter::coin(self : Jitter, one_in_n : Int) -> Bool {
  if one_in_n <= 0 { return false }
  self.next() < (65536 / one_in_n)
}

// ---------------------------------------------------------------------------
// Size bucketing — payload sizes are never stored exactly.
// ---------------------------------------------------------------------------

/// Round n down to the nearest multiple of bucket_size.
/// Default bucket_size of 512 loses at most 511 bytes of precision.
pub fn bucket(n : Int, bucket_size : Int) -> Int {
  let b = if bucket_size > 0 { bucket_size } else { 512 }
  (n / b) * b
}

/// Size category label — used as anchor names in the void so
/// the void accumulates which size ranges have been most active.
pub fn size_label(n : Int) -> String {
  if n < 512   { "xs"   }  // < 512 B  — tiny (ping, lifecycle)
  else if n < 2048  { "sm" }  // < 2 KB   — small (hover, short completion)
  else if n < 8192  { "md" }  // < 8 KB   — medium (completion list, diagnostics)
  else if n < 32768 { "lg" }  // < 32 KB  — large (big document edit)
  else              { "xl" }  // ≥ 32 KB  — xlarge (full workspace sync)
}
