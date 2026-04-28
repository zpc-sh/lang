///|
/// SDK slim-client layer over the Lang node runtime.
///
/// These wrappers keep each client profile minimal while reusing the same
/// Node wasm surface and host bridge.

///|
/// SDK client profile.
pub(all) enum SlimClientFlavor {
  Core
  Proxy
  ClaudeProcess
  Codex
} derive(Eq, Debug)

///|
impl Show for SlimClientFlavor with output(self, logger) {
  logger.write_string(
    match self {
      Core => "Core"
      Proxy => "Proxy"
      ClaudeProcess => "ClaudeProcess"
      Codex => "Codex"
    },
  )
}

///|
fn SlimClientFlavor::node_mode(self : SlimClientFlavor) -> @node.NodeMode {
  match self {
    Proxy => @node.Proxy
    Core | ClaudeProcess | Codex => @node.Headless
  }
}

///|
fn SlimClientFlavor::lsp_ops(self : SlimClientFlavor) -> @lsp.LspClientOps {
  match self {
    Core => @lsp.LspClientOps::json_rpc_core()
    Proxy => @lsp.LspClientOps::proxy()
    ClaudeProcess => @lsp.LspClientOps::claude_process()
    Codex => @lsp.LspClientOps::json_rpc_core()
  }
}

///|
/// Thin SDK wrapper around a Node instance configured for one client profile.
pub(all) struct SlimClient {
  flavor : SlimClientFlavor
  node : @node.Node
}

///|
/// Boot a slim client with explicit profile selection.
pub fn SlimClient::boot(
  node_id : String,
  flavor : SlimClientFlavor,
  host : @node.HostBridge,
) -> SlimClient {
  let node = @node.Node::boot_with_lsp_ops(
    node_id,
    flavor.node_mode(),
    host,
    flavor.lsp_ops(),
  )
  { flavor, node }
}

///|
/// Ingest raw LSP transport bytes.
pub fn SlimClient::ingest_lsp(self : SlimClient, bytes : Array[Byte]) -> Unit {
  self.node.ingest_lsp(bytes)
}

///|
/// Emit one JSON-RPC/LSP JSON payload.
pub fn SlimClient::emit_lsp(self : SlimClient, json : String) -> Unit {
  self.node.emit_lsp(json)
}

///|
/// Drain pending output frames to host transport.
pub fn SlimClient::drain_output(self : SlimClient) -> Array[Array[Byte]] {
  self.node.drain_output()
}

///|
/// Tick the runtime loop.
pub fn SlimClient::tick(self : SlimClient, now_ms : Int) -> Unit {
  self.node.tick(now_ms)
}

///|
/// Persist checkpoint and return CAS key.
pub fn SlimClient::checkpoint(self : SlimClient) -> String {
  self.node.checkpoint()
}

///|
/// Expose node stats for host observability.
pub fn SlimClient::stats(self : SlimClient) -> @node.NodeStats {
  self.node.stats()
}

///|
/// Underlying LSP implementation selected for this client.
pub fn SlimClient::lsp_impl(self : SlimClient) -> @lsp.LspClientImpl {
  self.node.lsp_impl()
}

///|
/// Profile label.
pub fn SlimClient::flavor(self : SlimClient) -> SlimClientFlavor {
  self.flavor
}
