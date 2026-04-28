///|
/// LSP client abstraction.
///
/// This module provides a trait-like boundary for LSP transport/message
/// handling so multiple client implementations can share the same Node kernel
/// integration points.

///|
/// Concrete client implementation identity.
pub(all) enum LspClientImpl {
  JsonRpcCore
  Proxy
  ClaudeProcess
  Custom(String)
} derive(Eq, Debug)

///|
impl Show for LspClientImpl with output(self, logger) {
  logger.write_string(
    match self {
      JsonRpcCore => "JsonRpcCore"
      Proxy => "Proxy"
      ClaudeProcess => "ClaudeProcess"
      Custom(name) => "Custom(\{name})"
    },
  )
}

///|
/// Trait-like function table for an LSP client implementation.
pub(all) struct LspClientOps {
  impl_id : LspClientImpl
  drain_frames : (Array[Byte]) -> (Array[Frame], Array[Byte])
  write_frame : (String) -> Array[Byte]
  parse_message_frame : (Frame) -> LspMessage
}

///|
/// Build a custom LSP client ops table.
pub fn LspClientOps::new(
  impl_id : LspClientImpl,
  drain_frames : (Array[Byte]) -> (Array[Frame], Array[Byte]),
  write_frame : (String) -> Array[Byte],
  parse_message_frame : (Frame) -> LspMessage,
) -> LspClientOps {
  { impl_id, drain_frames, write_frame, parse_message_frame }
}

///|
/// Standard JSON-RPC over Content-Length framing implementation.
pub fn LspClientOps::json_rpc_core() -> LspClientOps {
  LspClientOps::new(JsonRpcCore, frame_drain, frame_write, parse_frame)
}

///|
/// Standard proxy-mode LSP implementation.
pub fn LspClientOps::proxy() -> LspClientOps {
  let core = LspClientOps::json_rpc_core()
  { ..core, impl_id: Proxy }
}

///|
/// Standard Claude-process observer implementation.
pub fn LspClientOps::claude_process() -> LspClientOps {
  let core = LspClientOps::json_rpc_core()
  { ..core, impl_id: ClaudeProcess }
}

///|
/// Stateful LSP client runtime backed by LspClientOps.
pub(all) struct LspClient {
  ops : LspClientOps
  inbuf : Array[Byte]
}

///|
/// Create a new runtime client from ops.
pub fn LspClient::new(ops : LspClientOps) -> LspClient {
  { ops, inbuf: [] }
}

///|
/// Create a standard proxy-mode runtime client.
pub fn LspClient::proxy() -> LspClient {
  LspClient::new(LspClientOps::proxy())
}

///|
/// Create a standard Claude-process runtime client.
pub fn LspClient::claude_process() -> LspClient {
  LspClient::new(LspClientOps::claude_process())
}

///|
/// Client implementation identity.
pub fn LspClient::impl_id(self : LspClient) -> LspClientImpl {
  self.ops.impl_id
}

///|
/// Number of bytes currently buffered waiting for a full frame.
pub fn LspClient::pending_bytes(self : LspClient) -> Int {
  self.inbuf.length()
}

///|
/// Ingest raw bytes and return all complete parsed frames.
pub fn LspClient::ingest(self : LspClient, bytes : Array[Byte]) -> Array[Frame] {
  for b in bytes {
    self.inbuf.push(b)
  }
  let (frames, rest) = (self.ops.drain_frames)(self.inbuf)
  let next_buf = rest.copy()
  self.inbuf.clear()
  for b in next_buf {
    self.inbuf.push(b)
  }
  frames
}

///|
/// Encode a JSON body for transport.
pub fn LspClient::encode(self : LspClient, json : String) -> Array[Byte] {
  (self.ops.write_frame)(json)
}

///|
/// Parse a frame into a lightly-parsed message envelope.
pub fn LspClient::parse(self : LspClient, frame : Frame) -> LspMessage {
  (self.ops.parse_message_frame)(frame)
}
