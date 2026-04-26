///|
/// Host Externs — declarations for functions provided by the host runtime.
///
/// The node wasm module imports these from the host (AtomVM, WasmEdge,
/// or Elixir/wasmex). They provide I/O capabilities that wasm cannot
/// perform natively:
///   - Network I/O (TCP sockets for LSP, peer connections)
///   - Filesystem (CAS blob persistence)
///   - Clock (monotonic time for jitter, timeouts)
///   - Logging/tracing
///   - Host-specific extensions
///
/// In wasm-gc mode, these are declared as extern "wasm" imports.
/// For native testing, we provide stub implementations.
///
/// The node kernel calls these through the HostBridge abstraction,
/// which the host populates at init.

// ---------------------------------------------------------------------------
// Host capability descriptor
// ---------------------------------------------------------------------------

///|
/// What the host runtime can provide.
pub(all) struct HostCapabilities {
  has_network : Bool // can open TCP/UDP sockets
  has_filesystem : Bool // can read/write files
  has_clock : Bool // has monotonic clock
  has_logging : Bool // has structured logging
  has_crypto : Bool // has crypto primitives (hash, sign)
  host_name : String // "atomvm", "wasmedge", "wasmex", "stub"
} derive(Debug)

///|
/// Stub capabilities for testing (no real I/O).
pub fn HostCapabilities::stub() -> HostCapabilities {
  {
    has_network: false,
    has_filesystem: false,
    has_clock: true,
    has_logging: true,
    has_crypto: false,
    host_name: "stub",
  }
}

///|
/// Full capabilities for a real host runtime.
pub fn HostCapabilities::full(host_name : String) -> HostCapabilities {
  {
    has_network: true,
    has_filesystem: true,
    has_clock: true,
    has_logging: true,
    has_crypto: true,
    host_name,
  }
}

// ---------------------------------------------------------------------------
// Host bridge — the interface the kernel calls
// ---------------------------------------------------------------------------

///|
/// Pending I/O operation result.
pub(all) enum IoResult {
  Ok(Array[Byte]) // success with data
  Err(String) // error message
  Pending // not yet complete
} derive(Debug)

///|
/// The host bridge — function table for host-provided I/O.
///
/// In wasm, these would be extern imports. Here we model them as
/// a struct of closures so the host can populate them at init.
pub(all) struct HostBridge {
  capabilities : HostCapabilities

  // Clock
  mono_now_ms : () -> Int // monotonic time in milliseconds

  // Logging
  log_trace : (String) -> Unit // trace-level log
  log_info : (String) -> Unit // info-level log
  log_warn : (String) -> Unit // warning-level log
  log_error : (String) -> Unit // error-level log

  // Blob I/O (CAS persistence)
  blob_put : (String, Array[Byte]) -> Bool // key, data → success
  blob_get : (String) -> Array[Byte]? // key → data or None
  blob_has : (String) -> Bool // key → exists?

  // Network (optional — may be no-ops)
  net_send : (Int, Array[Byte]) -> Bool // fd, data → success
  net_recv : (Int) -> Array[Byte]? // fd → data or None

  // Network socket management (wasm-gc host functions; no-ops in native)
  net_listen : (Int) -> Int // port → listener fd, -1 on error
  net_accept : (Int) -> Int? // listener fd → conn fd or None
  net_connect : (String, Int) -> Int? // host, port → conn fd or None

  // Crypto primitives (wasm-gc host functions; no-ops in stub)
  crypto_hash : (Array[Byte]) -> Array[Byte] // sha-256 or blake3
  crypto_sign : (Array[Byte], Array[Byte]) -> Array[Byte] // msg, key → sig
  crypto_verify : (Array[Byte], Array[Byte], Array[Byte]) -> Bool // msg, sig, pubkey
}

///|
/// Create a stub host bridge for testing.
pub fn HostBridge::stub() -> HostBridge {
  let store : Map[String, Array[Byte]] = {}
  let clock : Ref[Int] = { val: 0 }
  {
    capabilities: HostCapabilities::stub(),
    mono_now_ms: fn() -> Int {
      clock.val = clock.val + 1
      clock.val
    },
    log_trace: fn(_msg : String) -> Unit { () },
    log_info: fn(_msg : String) -> Unit { () },
    log_warn: fn(_msg : String) -> Unit { () },
    log_error: fn(_msg : String) -> Unit { () },
    blob_put: fn(key : String, data : Array[Byte]) -> Bool {
      store[key] = data
      true
    },
    blob_get: fn(key : String) -> Array[Byte]? { store.get(key) },
    blob_has: fn(key : String) -> Bool { store.get(key) is Some(_) },
    net_send: fn(_fd : Int, _data : Array[Byte]) -> Bool { false },
    net_recv: fn(_fd : Int) -> Array[Byte]? { None },
    net_listen: fn(_port : Int) -> Int { -1 },
    net_accept: fn(_fd : Int) -> Int? { None },
    net_connect: fn(_host : String, _port : Int) -> Int? { None },
    crypto_hash: fn(data : Array[Byte]) -> Array[Byte] {
      // FNV-1a stub — real impl provided by host at runtime
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
    },
    crypto_sign: fn(_msg : Array[Byte], _key : Array[Byte]) -> Array[Byte] {
      Array::make(64, b'\x00') // stub — no-op
    },
    crypto_verify: fn(
      _msg : Array[Byte],
      _sig : Array[Byte],
      _pubkey : Array[Byte],
    ) -> Bool {
      false // stub — always rejects
    },
  }
}
