///|
/// mulsp — self-emitted specification.
///
/// RECURSIVE SPEC PATTERN
/// ──────────────────────
/// This file is the canonical spec for the `mulsp` partition. It serves two
/// roles simultaneously:
///
///   1. DOCUMENTATION — every public function in `mulsp.mbt` is listed here
///      with its category, complexity class, functional type, and failure mode.
///      A Claude reading this file gets the full API surface in one pass.
///
///   2. TEST FIXTURE — `mulsp_spec()` returns the spec as an `Array[MulspFnSpec]`.
///      `mulsp_spec_test.mbt` uses that array to drive coverage checks, ensuring
///      the implementation matches this declared surface.
///
/// HOW TO APPLY THIS PATTERN TO ANOTHER PARTITION
/// ───────────────────────────────────────────────
///   a. Create `<pkg>/<pkg>_spec.mbt` — copy this file, replace types and entries.
///   b. Create `<pkg>/<pkg>_spec_test.mbt` — probe spec data + exercise real API.
///   c. A fresh Claude starts by reading `<pkg>_spec.mbt` to understand scope.
///   d. Every new function added to `<pkg>.mbt` must get an entry in `<pkg>_spec()`.
///      The spec test enforces category counts, catching omissions at build time.
///
/// MULSP PARTITION LAYOUT (25 public functions)
/// ─────────────────────────────────────────────
///   Lifecycle     7   new, attach, activate, delegate, quiesce, revoke, reattach
///   Fork          4   fork, fork_as, is_clone, parent_id
///   Mutation      8   bind_procsi, bind_app, add_capability, emit_residue,
///                     update_trail, checkpoint, set_projection, set_fingerprint
///   Query         4   is_active, is_terminal, can_accept_work, capability_count
///   Serialization 2   to_bytes, from_bytes

// ---------------------------------------------------------------------------
// Metadata types
// ---------------------------------------------------------------------------

///|
/// Functional category — which subsystem a mulsp function belongs to.
pub(all) enum MulspCategory {
  Lifecycle     // state machine transitions (Dormant → … → Revoked)
  Fork          // delegation and clone operations
  Mutation      // immutable field updates (builder pattern)
  Query         // predicates and scalar reads
  Serialization // wire codec (to_bytes / from_bytes)
} derive(Eq, Debug)

///|
impl Show for MulspCategory with output(self, logger) {
  logger.write_string(
    match self {
      Lifecycle => "Lifecycle"
      Fork => "Fork"
      Mutation => "Mutation"
      Query => "Query"
      Serialization => "Serialization"
    },
  )
}

///|
/// Complexity / approximate LOC class of a mulsp function.
pub(all) enum SpecSize {
  Trivial // 1–3 lines: single match arm or field access
  Small   // 4–15 lines: simple branching or copy-update
  Medium  // 16–40 lines: non-trivial multi-branch logic
  Large   // 40+ lines: full codec or deeply nested structure
} derive(Eq, Debug)

///|
impl Show for SpecSize with output(self, logger) {
  logger.write_string(
    match self {
      Trivial => "Trivial"
      Small => "Small"
      Medium => "Medium"
      Large => "Large"
    },
  )
}

///|
/// Functional type — what kind of operation a function performs.
pub(all) enum MulspFuncType {
  Constructor // creates a fresh MulspState
  Transition  // lifecycle state change, returns MulspState? (may fail)
  Builder     // immutable field update, always returns MulspState
  Predicate   // Bool query
  Counter     // Int / scalar query
  Codec       // serialization (to_bytes → Array[Byte]; from_bytes → MulspState?)
  Delegation  // fork producing (parent, child) pair, returns (MulspState, MulspState)?
} derive(Eq, Debug)

///|
impl Show for MulspFuncType with output(self, logger) {
  logger.write_string(
    match self {
      Constructor => "Constructor"
      Transition => "Transition"
      Builder => "Builder"
      Predicate => "Predicate"
      Counter => "Counter"
      Codec => "Codec"
      Delegation => "Delegation"
    },
  )
}

///|
/// Spec record for one public function in the mulsp partition.
pub(all) struct MulspFnSpec {
  name      : String
  category  : MulspCategory
  size      : SpecSize
  func_type : MulspFuncType
  can_fail  : Bool // true → return type is Option (may be None)
} derive(Debug)

// ---------------------------------------------------------------------------
// The spec — mulsp presenting its own API surface
// ---------------------------------------------------------------------------

///|
/// Returns the canonical spec for all public functions in `mulsp.mbt`.
///
/// Ordered: Lifecycle → Fork → Mutation → Query → Serialization.
/// The total count (25) and per-category counts are enforced by spec tests.
/// When a new function is added to `mulsp.mbt`, add an entry here; the test
/// will catch count drift before review.
pub fn mulsp_spec() -> Array[MulspFnSpec] {
  [
    // ── Lifecycle ────────────────────────────────────────────────────────────
    {
      name: "new",
      category: Lifecycle,
      size: Small,
      func_type: Constructor,
      can_fail: false,
    },
    {
      name: "attach",
      category: Lifecycle,
      size: Small,
      func_type: Transition,
      can_fail: true,
    },
    {
      name: "activate",
      category: Lifecycle,
      size: Trivial,
      func_type: Transition,
      can_fail: true,
    },
    {
      name: "delegate",
      category: Lifecycle,
      size: Small,
      func_type: Transition,
      can_fail: true,
    },
    {
      name: "quiesce",
      category: Lifecycle,
      size: Trivial,
      func_type: Transition,
      can_fail: true,
    },
    {
      name: "revoke",
      category: Lifecycle,
      size: Trivial,
      func_type: Builder,
      can_fail: false,
    },
    {
      name: "reattach",
      category: Lifecycle,
      size: Trivial,
      func_type: Transition,
      can_fail: true,
    },
    // ── Fork / Delegation ────────────────────────────────────────────────────
    {
      name: "fork",
      category: Fork,
      size: Medium,
      func_type: Delegation,
      can_fail: true,
    },
    {
      name: "fork_as",
      category: Fork,
      size: Small,
      func_type: Delegation,
      can_fail: true,
    },
    {
      name: "is_clone",
      category: Fork,
      size: Trivial,
      func_type: Predicate,
      can_fail: false,
    },
    {
      name: "parent_id",
      category: Fork,
      size: Trivial,
      func_type: Predicate,
      can_fail: true,
    },
    // ── Mutation (builder pattern) ────────────────────────────────────────────
    {
      name: "bind_procsi",
      category: Mutation,
      size: Trivial,
      func_type: Builder,
      can_fail: false,
    },
    {
      name: "bind_app",
      category: Mutation,
      size: Trivial,
      func_type: Builder,
      can_fail: false,
    },
    {
      name: "add_capability",
      category: Mutation,
      size: Small,
      func_type: Builder,
      can_fail: false,
    },
    {
      name: "emit_residue",
      category: Mutation,
      size: Trivial,
      func_type: Builder,
      can_fail: false,
    },
    {
      name: "update_trail",
      category: Mutation,
      size: Trivial,
      func_type: Builder,
      can_fail: false,
    },
    {
      name: "checkpoint",
      category: Mutation,
      size: Trivial,
      func_type: Builder,
      can_fail: false,
    },
    {
      name: "set_projection",
      category: Mutation,
      size: Trivial,
      func_type: Builder,
      can_fail: false,
    },
    {
      name: "set_fingerprint",
      category: Mutation,
      size: Trivial,
      func_type: Builder,
      can_fail: false,
    },
    // ── Query ────────────────────────────────────────────────────────────────
    {
      name: "is_active",
      category: Query,
      size: Trivial,
      func_type: Predicate,
      can_fail: false,
    },
    {
      name: "is_terminal",
      category: Query,
      size: Trivial,
      func_type: Predicate,
      can_fail: false,
    },
    {
      name: "can_accept_work",
      category: Query,
      size: Trivial,
      func_type: Predicate,
      can_fail: false,
    },
    {
      name: "capability_count",
      category: Query,
      size: Trivial,
      func_type: Counter,
      can_fail: false,
    },
    // ── Serialization ────────────────────────────────────────────────────────
    {
      name: "to_bytes",
      category: Serialization,
      size: Large,
      func_type: Codec,
      can_fail: false,
    },
    {
      name: "from_bytes",
      category: Serialization,
      size: Large,
      func_type: Codec,
      can_fail: true,
    },
  ]
}

// ---------------------------------------------------------------------------
// Spec query helpers
// ---------------------------------------------------------------------------

///|
/// All spec entries for a given category.
pub fn spec_by_category(cat : MulspCategory) -> Array[MulspFnSpec] {
  let result : Array[MulspFnSpec] = []
  for entry in mulsp_spec() {
    if entry.category == cat {
      result.push(entry)
    }
  }
  result
}

///|
/// All spec entries whose return type is Option (can_fail = true).
pub fn spec_fallible() -> Array[MulspFnSpec] {
  let result : Array[MulspFnSpec] = []
  for entry in mulsp_spec() {
    if entry.can_fail {
      result.push(entry)
    }
  }
  result
}

///|
/// All spec entries of a given functional type.
pub fn spec_by_type(ft : MulspFuncType) -> Array[MulspFnSpec] {
  let result : Array[MulspFnSpec] = []
  for entry in mulsp_spec() {
    if entry.func_type == ft {
      result.push(entry)
    }
  }
  result
}

///|
/// Find a spec entry by function name. Returns None if not in spec.
pub fn spec_lookup(name : String) -> MulspFnSpec? {
  for entry in mulsp_spec() {
    if entry.name == name {
      return Some(entry)
    }
  }
  None
}
