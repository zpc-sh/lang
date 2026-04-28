///|
/// Plugin Registry — dynamic plugin loading and lifecycle management.
///
/// Plugins are wasm modules loaded by CAS hash. Each plugin:
///   - Has a unique ID and name
///   - Carries procsi identity (.prc section)
///   - Exposes an ABI contract (init, handle, query exports)
///   - Receives bus messages matching its topic subscriptions
///   - Can emit output back through the bus
///
/// The registry manages plugin state, routing, and lifecycle:
///   Loading → Ready → Active → Suspended → Unloaded
///
/// In the current implementation, plugins are represented as metadata
/// entries. Actual wasm instantiation requires the host runtime (Mu).

// ---------------------------------------------------------------------------
// Plugin state
// ---------------------------------------------------------------------------

///|
/// Lifecycle state of a loaded plugin.
pub(all) enum PluginState {
  Loading // wasm bytes being fetched/parsed
  Ready // parsed, exports validated, not yet started
  Active // running, receiving bus messages
  Suspended // temporarily paused
  Unloaded // removed from registry
  Failed(String) // load or runtime error
} derive(Eq, Debug)

///|
impl Show for PluginState with output(self, logger) {
  logger.write_string(
    match self {
      Loading => "Loading"
      Ready => "Ready"
      Active => "Active"
      Suspended => "Suspended"
      Unloaded => "Unloaded"
      Failed(msg) => "Failed(\{msg})"
    },
  )
}

// ---------------------------------------------------------------------------
// Plugin ABI contract
// ---------------------------------------------------------------------------

///|
/// The exports a plugin wasm must provide.
pub(all) struct PluginAbi {
  has_init : Bool // plugin_init() -> i32
  has_handle : Bool // plugin_handle(topic: i32, payload_ptr: i32, len: i32) -> i32
  has_query : Bool // plugin_query(query_ptr: i32, len: i32) -> i32
  has_tick : Bool // plugin_tick(now_ms: i32) -> i32
  has_dispose : Bool // plugin_dispose() -> void
} derive(Debug)

///|
pub fn PluginAbi::empty() -> PluginAbi {
  {
    has_init: false,
    has_handle: false,
    has_query: false,
    has_tick: false,
    has_dispose: false,
  }
}

///|
/// Validate that minimum ABI requirements are met.
pub fn PluginAbi::is_valid(self : PluginAbi) -> Bool {
  // At minimum, a plugin must have init and handle
  self.has_init && self.has_handle
}

// ---------------------------------------------------------------------------
// Plugin entry
// ---------------------------------------------------------------------------

///|
/// A registered plugin in the node.
pub(all) struct PluginEntry {
  id : String // unique plugin ID (hash of wasm bytes)
  name : String // human-readable name
  mut state : PluginState
  abi : PluginAbi
  cas_key : String // CAS hash of the wasm bytes
  topics : Array[@node.Topic] // bus topics this plugin subscribes to
  // Procsi identity (extracted from .prc section)
  mut procsi_locus : String?
  mut procsi_tier : String?
  mut is_core_capsule : Bool
  mut wasi_enabled : Bool
  mut replace_generation : Int
  mut handler_effect_ref : String?
  // Runtime state
  mut invocations : Int // total handle() calls
  mut last_tick_ms : Int // last tick timestamp
  // Output buffer
  output : Array[Array[Byte]]
} derive(Debug)

///|
pub fn PluginEntry::new(
  id : String,
  name : String,
  cas_key : String,
  abi : PluginAbi,
  topics : Array[@node.Topic],
) -> PluginEntry {
  {
    id,
    name,
    state: Loading,
    abi,
    cas_key,
    topics,
    procsi_locus: None,
    procsi_tier: None,
    is_core_capsule: false,
    wasi_enabled: false,
    replace_generation: 0,
    handler_effect_ref: None,
    invocations: 0,
    last_tick_ms: 0,
    output: [],
  }
}

///|
/// Transition to Ready state.
pub fn PluginEntry::mark_ready(self : PluginEntry) -> Unit {
  match self.state {
    Loading => self.state = Ready
    _ => ()
  }
}

///|
/// Activate the plugin.
pub fn PluginEntry::activate(self : PluginEntry) -> Unit {
  match self.state {
    Ready | Suspended => self.state = Active
    _ => ()
  }
}

///|
/// Suspend the plugin.
pub fn PluginEntry::suspend(self : PluginEntry) -> Unit {
  match self.state {
    Active => self.state = Suspended
    _ => ()
  }
}

///|
/// Unload the plugin.
pub fn PluginEntry::unload(self : PluginEntry) -> Unit {
  self.state = Unloaded
}

///|
/// Mark as failed with error message.
pub fn PluginEntry::fail(self : PluginEntry, msg : String) -> Unit {
  self.state = Failed(msg)
}

///|
/// Is the plugin able to receive messages?
pub fn PluginEntry::is_active(self : PluginEntry) -> Bool {
  self.state == Active
}

///|
/// Drain output from the plugin's output buffer.
pub fn PluginEntry::drain_output(self : PluginEntry) -> Array[Array[Byte]] {
  let out = self.output.copy()
  self.output.clear()
  out
}

///|
/// Record an invocation.
pub fn PluginEntry::record_invocation(self : PluginEntry, now_ms : Int) -> Unit {
  self.invocations = self.invocations + 1
  self.last_tick_ms = now_ms
}

///|
/// Set procsi identity from extracted .prc section.
pub fn PluginEntry::set_procsi(
  self : PluginEntry,
  locus : String,
  tier : String,
) -> Unit {
  self.procsi_locus = Some(locus)
  self.procsi_tier = Some(tier)
}

///|
pub fn PluginEntry::mark_core_capsule(
  self : PluginEntry,
  wasi_enabled? : Bool = true,
) -> Unit {
  self.is_core_capsule = true
  self.wasi_enabled = wasi_enabled
}

///|
pub fn PluginEntry::record_handler_effect(
  self : PluginEntry,
  effect_ref : String,
  generation : Int,
) -> Unit {
  self.handler_effect_ref = Some(effect_ref)
  self.replace_generation = generation
}

// ---------------------------------------------------------------------------
// Plugin Registry
// ---------------------------------------------------------------------------

///|
/// The node's plugin registry — manages all loaded plugins.
pub(all) struct PluginRegistry {
  plugins : Array[PluginEntry]
  mut load_count : Int
  mut fail_count : Int
} derive(Debug)

///|
pub fn PluginRegistry::new() -> PluginRegistry {
  { plugins: [], load_count: 0, fail_count: 0 }
}

///|
/// Register a new plugin. Returns its index.
pub fn PluginRegistry::register(
  self : PluginRegistry,
  id : String,
  name : String,
  cas_key : String,
  abi : PluginAbi,
  topics : Array[@node.Topic],
) -> Int {
  if name == "procsi" {
    match self.find_by_name("procsi") {
      Some(existing) => {
        // procsi is a reserved core capsule/plugin. Keep existing instance
        // stable unless an explicit replacement effect is used.
        if existing.is_core_capsule &&
          existing.state != Unloaded &&
          existing.cas_key != cas_key {
          self.fail_count = self.fail_count + 1
          return match self.find_index_by_id(existing.id) {
            Some(idx) => idx
            None => -1
          }
        }
      }
      None => ()
    }
  }
  let idx = self.plugins.length()
  let entry = PluginEntry::new(id, name, cas_key, abi, topics)
  if name == "procsi" {
    entry.mark_core_capsule()
    entry.procsi_tier = Some("core-capsule")
  }
  self.plugins.push(entry)
  self.load_count = self.load_count + 1
  idx
}

///|
fn PluginRegistry::find_index_by_id(self : PluginRegistry, id : String) -> Int? {
  let mut i = 0
  for p in self.plugins {
    if p.id == id {
      return Some(i)
    }
    i = i + 1
  }
  None
}

///|
fn PluginRegistry::find_index_by_name(self : PluginRegistry, name : String) -> Int? {
  let mut i = 0
  for p in self.plugins {
    if p.name == name {
      return Some(i)
    }
    i = i + 1
  }
  None
}

///|
/// Replace the reserved procsi core capsule via an explicit handler effect.
///
/// This is the only path that may swap an existing live procsi module.
pub fn PluginRegistry::replace_core_procsi_wasi(
  self : PluginRegistry,
  id : String,
  cas_key : String,
  abi : PluginAbi,
  topics : Array[@node.Topic],
  handler_effect_ref : String,
) -> Int {
  let next_generation = match self.find_index_by_name("procsi") {
    Some(idx) => {
      let existing = self.plugins[idx]
      existing.unload()
      existing.replace_generation + 1
    }
    None => 0
  }
  let next_idx = self.plugins.length()
  let entry = PluginEntry::new(id, "procsi", cas_key, abi, topics)
  entry.mark_core_capsule(wasi_enabled=true)
  entry.procsi_tier = Some("core-capsule")
  entry.record_handler_effect(handler_effect_ref, next_generation)
  self.plugins.push(entry)
  self.load_count = self.load_count + 1
  next_idx
}

///|
/// Find a plugin by ID.
pub fn PluginRegistry::find(self : PluginRegistry, id : String) -> PluginEntry? {
  for p in self.plugins {
    if p.id == id {
      return Some(p)
    }
  }
  None
}

///|
/// Find a plugin by name.
pub fn PluginRegistry::find_by_name(
  self : PluginRegistry,
  name : String,
) -> PluginEntry? {
  for p in self.plugins {
    if p.name == name {
      return Some(p)
    }
  }
  None
}

///|
/// Get all active plugins.
pub fn PluginRegistry::active_plugins(
  self : PluginRegistry,
) -> Array[PluginEntry] {
  let out : Array[PluginEntry] = []
  for p in self.plugins {
    if p.is_active() {
      out.push(p)
    }
  }
  out
}

///|
/// Get all plugins subscribed to a given topic.
pub fn PluginRegistry::subscribers_for(
  self : PluginRegistry,
  topic : @node.Topic,
) -> Array[PluginEntry] {
  let out : Array[PluginEntry] = []
  for p in self.plugins {
    if p.is_active() {
      for t in p.topics {
        if t == topic {
          out.push(p)
          break
        }
      }
    }
  }
  out
}

///|
/// Number of registered plugins.
pub fn PluginRegistry::count(self : PluginRegistry) -> Int {
  self.plugins.length()
}

///|
/// Number of active plugins.
pub fn PluginRegistry::active_count(self : PluginRegistry) -> Int {
  let mut n = 0
  for p in self.plugins {
    if p.is_active() {
      n = n + 1
    }
  }
  n
}

///|
/// Registry statistics.
pub(all) struct RegistryStats {
  total : Int
  active : Int
  loading : Int
  suspended : Int
  failed : Int
  unloaded : Int
} derive(Debug)

///|
pub fn PluginRegistry::stats(self : PluginRegistry) -> RegistryStats {
  let mut active = 0
  let mut loading = 0
  let mut suspended = 0
  let mut failed = 0
  let mut unloaded = 0
  for p in self.plugins {
    match p.state {
      Active => active = active + 1
      Loading => loading = loading + 1
      Ready => loading = loading + 1
      Suspended => suspended = suspended + 1
      Failed(_) => failed = failed + 1
      Unloaded => unloaded = unloaded + 1
    }
  }
  { total: self.plugins.length(), active, loading, suspended, failed, unloaded }
}
