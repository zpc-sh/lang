///|
/// Gopher per-connection handler.
///
/// Stateless single-request: read selector line, dispatch, write response, close.

///|
/// Context the Gopher handler needs to build responses.
pub(all) struct GopherContext {
  node_id : String
  epoch : Int
  mode : String
  tier : String
  overlay : String
  plugins : Array[String]
  peers : Array[@gopher.GopherPeerSummary]
  oci_types : Array[String]
  nntp_groups : Array[(String, Int, Int)]
  host : String
  port : Int
  lookup_blob : (String) -> Array[Byte]?
}

///|
pub fn GopherContext::from_node(
  n : @node.Node,
  host : String,
  port : Int,
) -> GopherContext {
  let s = n.stats()
  let mode_str = match s.mode {
    @node.NodeMode::Proxy => "Proxy"
    @node.NodeMode::Emergent => "Emergent"
    @node.NodeMode::Plugin => "Plugin"
    @node.NodeMode::Headless => "Headless"
  }
  {
    node_id: s.node_id,
    epoch: s.epoch,
    mode: mode_str,
    tier: "standard",
    overlay: "lang",
    plugins: [],
    peers: [],
    oci_types: ["application/vnd.loci.leaf.v1+json"],
    nntp_groups: [],
    host,
    port,
    lookup_blob: fn(key : String) -> Array[Byte]? {
      match n.cas_query(key) {
        None => None
        Some(env) => Some(env.data)
      }
    },
  }
}

///|
/// Handle one accepted Gopher connection.
pub async fn handle_gopher_connection(
  conn : @socket.Tcp,
  ctx : GopherContext,
) -> Unit {
  defer conn.close()
  let selector = match conn.read_until("\r\n") {
    None => ""
    Some(line) => line
  }
  let request_bytes = Bytes::of_string("\{selector}\r\n").iter().collect()
  let response = match @gopher.GopherRequest::parse(request_bytes) {
    None => @gopher.GopherResponse::Menu(@gopher.build_not_found_response(selector))
    Some(req) =>
      @gopher.dispatch_request(
        req,
        ctx.node_id,
        ctx.epoch,
        ctx.mode,
        ctx.tier,
        ctx.overlay,
        false,
        ctx.plugins,
        ctx.peers,
        ctx.oci_types,
        ctx.nntp_groups,
        ctx.host,
        ctx.port,
        ctx.lookup_blob,
      )
  }
  conn.write(Bytes::from_array(response.encode()[:]))
}
