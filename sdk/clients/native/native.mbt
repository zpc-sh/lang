///|
/// Native LSP client shim for lazy/deferred loci execution.
///
/// This shim is handler-first (no hooks):
/// - each LSP function execution is wrapped as its own loci dropbox item
/// - mulsp/muyata packets are captured at emit time
/// - responses are resolved lazily through explicit await/drain APIs
/// - one runtime process can ship as a single binary

///|
pub(all) enum DeferredStatus {
  Queued
  Awaiting
  StreamingMedia
  Completed
  Failed
} derive(Eq, Debug)

///|
/// Dual-tape memory representation for the mulsp FST.
/// Memory 0 is standard heap, Memory 1 is the 1MB code cave.
pub(all) struct NativeCodeCave {
  capacity : Int // fixed 1MB: 1048576
  mut secret_tape : Array[Byte] // Memory 1
} derive(Debug)

///|
/// Media streaming mesh proxy for Vision/Audio transformations.
pub(all) struct MediaMeshProxy {
  plugin_dimension : String // e.g., "vision", "pdf"
  mut total_bytes_streamed : Int
} derive(Debug)

///|
/// Initializing the proxy with standard Vision dimension (like avici-plugin-vision).
pub fn MediaMeshProxy::vision() -> MediaMeshProxy {
  { plugin_dimension: "vision", total_bytes_streamed: 0 }
}

///|
pub(all) struct LociDropboxItem {
  loci_id : String
  function_name : String
  request_id : String
  inverse_function : String
  mulsp_packet : @mulsp.MulspState
  muyata_packet : @muyata.MuyataProfile
  cave_memory : NativeCodeCave
  media_proxy : MediaMeshProxy?
  wire : Array[Byte]
  mut response : @lsp.LspMessage?
  mut status : DeferredStatus
} derive(Debug)

///|
fn native_function_capability(function_name : String) -> String {
  "fn:" + function_name
}

///|
fn native_inverse_capability(function_name : String) -> String {
  "inverse:" + function_name
}

///|
fn normalize_request_id(request_id : String) -> String {
  let len = request_id.length()
  if len >= 2 &&
    request_id.has_prefix("\"") &&
    request_id[len - 1:len].to_string() == "\"" {
    request_id[1:len - 1].to_string()
  } else {
    request_id
  }
}

///|
fn native_mulsp_packet(
  function_name : String,
  request_id : String,
  ratio_loci : String,
  execution_surface : String,
) -> @mulsp.MulspState {
  let base = @mulsp.MulspState::new(
    "lang:lsp:" + function_name + ":" + request_id,
    ratio_loci,
    execution_surface,
    "lang",
  )
  match @lsp.wrap_mulsp(function_name) {
    None => base.add_capability(native_function_capability(function_name))
    Some(block) =>
      base
      .add_capability(native_function_capability(function_name))
      .add_capability(native_inverse_capability(block.inverse_function))
      .add_capability("seed:" + block.seed.to_string())
  }
}

///|
fn native_muyata_packet(function_name : String, execution_surface : String) -> @muyata.MuyataProfile {
  @muyata.MuyataProfile::new(
    "lang",
    "generic",
    "lsp",
    @muyata.Translation,
    execution_surface,
    "lang",
    "fn:" + function_name,
  )
}

///|
/// Baremetal FFI endpoint representing a physical device (e.g., Raspberry Pi via USB).
pub(all) struct BaremetalEndpoint {
  device_id : String
  ffi_descriptor : String // FFI binding to USB gadget / raw hardware
  active_mulsp : @mulsp.MulspState?
} derive(Debug)

///|
/// A squad of baremetal endpoints piloted simultaneously.
/// The union transducer merges their output tapes, but the perception collapse
/// risk happens if the squad size exceeds the pilot's cognitive window.
pub(all) struct NativeSquad {
  squad_id : String
  endpoints : Array[BaremetalEndpoint]
  mut perception_collapsed : Bool
} derive(Debug)

///|
pub(all) struct NativeLspShim {
  client : @lsp.LspClient
  ratio_loci : String
  vfs_belly_hash : String // The entire filesystem reference stored in its belly
  execution_surface : String
  outbox : Array[Array[Byte]]
  dropbox : Array[LociDropboxItem]
}

///|
pub fn NativeLspShim::boot_proxy(
  ratio_loci : String,
  vfs_belly_hash : String,
  execution_surface? : String = "native-bin",
) -> NativeLspShim {
  {
    client: @lsp.LspClient::proxy(),
    ratio_loci,
    vfs_belly_hash,
    execution_surface,
    outbox: [],
    dropbox: [],
  }
}

///|
pub fn NativeLspShim::enqueue_emit(
  self : NativeLspShim,
  loci_id : String,
  function_name : String,
  request_id : String,
  json : String,
) -> LociDropboxItem? {
  match @lsp.wrap_mulsp(function_name) {
    None => None
    Some(block) => {
      let wire = self.client.encode(json)
      let cave = { capacity: 1048576, secret_tape: [] } // 1MB Code Cave constraint
      
      // We inject the VFS belly reference directly into the MulspState scope root
      let mulsp = native_mulsp_packet(
          function_name,
          request_id,
          self.ratio_loci,
          self.execution_surface,
        ).set_projection(self.vfs_belly_hash)

      let item : LociDropboxItem = {
        loci_id,
        function_name,
        request_id,
        inverse_function: block.inverse_function,
        mulsp_packet: mulsp,
        muyata_packet: native_muyata_packet(function_name, self.execution_surface),
        cave_memory: cave,
        media_proxy: if function_name.contains("vision") { Some(MediaMeshProxy::vision()) } else { None },
        wire,
        response: None,
        status: Awaiting,
      }
      self.outbox.push(wire)
      self.dropbox.push(item)
      Some(item)
    }
  }
}

///|
pub fn NativeLspShim::drain_outbox(self : NativeLspShim) -> Array[Array[Byte]] {
  let out = self.outbox.copy()
  self.outbox.clear()
  out
}

///|
pub fn NativeLspShim::ingest_response_bytes(
  self : NativeLspShim,
  bytes : Array[Byte],
) -> Array[@lsp.LspMessage] {
  let resolved : Array[@lsp.LspMessage] = []
  let frames = self.client.ingest(bytes)
  for frame in frames {
    let msg = self.client.parse(frame)
    resolved.push(msg)
    match msg.id {
      None => ()
      Some(request_id) => {
        let response_id = normalize_request_id(request_id)
        let mut idx = 0
        while idx < self.dropbox.length() {
          let entry = self.dropbox[idx]
          if normalize_request_id(entry.request_id) == response_id &&
            entry.status == Awaiting {
            self.dropbox[idx] = {
              ..entry,
              response: Some(msg),
              status: Completed,
            }
            break
          }
          idx = idx + 1
        }
      }
    }
  }
  resolved
}

///|
pub fn NativeLspShim::await_response(
  self : NativeLspShim,
  request_id : String,
) -> @lsp.LspMessage? {
  let wanted = normalize_request_id(request_id)
  for entry in self.dropbox {
    if normalize_request_id(entry.request_id) == wanted {
      return entry.response
    }
  }
  None
}

///|
pub fn NativeLspShim::dropbox_for_loci(
  self : NativeLspShim,
  loci_id : String,
) -> Array[LociDropboxItem] {
  let out : Array[LociDropboxItem] = []
  for entry in self.dropbox {
    if entry.loci_id == loci_id {
      out.push(entry)
    }
  }
  out
}

///|
pub fn NativeLspShim::pending_count(self : NativeLspShim) -> Int {
  let mut n = 0
  for entry in self.dropbox {
    if entry.status == Awaiting || entry.status == Queued {
      n = n + 1
    }
  }
  n
}

///|
pub fn NativeLspShim::resolved_count(self : NativeLspShim) -> Int {
  let mut n = 0
  for entry in self.dropbox {
    if entry.status == Completed {
      n = n + 1
    }
  }
  n
}
