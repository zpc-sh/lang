///|
/// Slim SDK profile for an LSP proxy client.

///|
pub fn boot(node_id : String, host : @node.HostBridge) -> @core.SlimClient {
  @core.SlimClient::boot(node_id, @core.Proxy, host)
}
