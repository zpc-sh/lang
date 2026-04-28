///|
/// Slim SDK profile for Claude process observation/interposition.

///|
pub fn boot(node_id : String, host : @node.HostBridge) -> @core.SlimClient {
  @core.SlimClient::boot(node_id, @core.ClaudeProcess, host)
}
