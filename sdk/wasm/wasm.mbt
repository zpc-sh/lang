///|
/// Wasm-facing slim client boot entrypoints.
///
/// Each function returns a slim client configured for one profile while
/// preserving a shared node/wasm runtime surface.

///|
pub fn boot_jsonrpc(
  node_id : String,
  host : @node.HostBridge,
) -> @core.SlimClient {
  @jsonrpc.boot(node_id, host)
}

///|
pub fn boot_proxy(node_id : String, host : @node.HostBridge) -> @core.SlimClient {
  @proxy.boot(node_id, host)
}

///|
pub fn boot_claude(node_id : String, host : @node.HostBridge) -> @core.SlimClient {
  @claude.boot(node_id, host)
}

///|
pub fn boot_codex(node_id : String, host : @node.HostBridge) -> @core.SlimClient {
  @codex_client.boot(node_id, host)
}

///|
pub fn boot_flavor(
  node_id : String,
  flavor : @core.SlimClientFlavor,
  host : @node.HostBridge,
) -> @core.SlimClient {
  @core.SlimClient::boot(node_id, flavor, host)
}
