///|
/// Slim SDK profile for a JSON-RPC core client.

///|
pub fn boot(node_id : String, host : @node.HostBridge) -> @core.SlimClient {
  @core.SlimClient::boot(node_id, @core.Core, host)
}
