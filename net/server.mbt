///|
/// Top-level lang node server.
///
/// Spawns one listener per protocol inside a TaskGroup:
///   - NNTP TCP on `nntp_port`
///   - Gopher TCP on `gopher_port`
///   - GMU/1 UDP on `gmu_port`
///   - Peer discovery loop

pub let default_nntp_port : Int = 1119
pub let default_gopher_port : Int = 1070
pub let default_gmu_port : Int = 1777

///|
/// Boot all network listeners for a lang node.
pub async fn run_node_server(
  node : @node.Node,
  host_addr : String,
  nntp_port : Int,
  gopher_port : Int,
  gmu_port : Int,
  seed_peers : Array[String],
) -> Unit {
  let stats = node.stats()
  let node_id = stats.node_id
  let gopher_ctx = GopherContext::from_node(node, host_addr, gopher_port)
  let finger = @finger.FingerState::new()
  @async.with_task_group(root => {
    let nntp_addr = @socket.Addr::parse("\{host_addr}:\{nntp_port}")
    let nntp_srv = @socket.TcpServer::new(nntp_addr, reuse_addr=true)
    root.spawn_bg(
      allow_failure=true,
      () =>
        nntp_srv.run_forever(
          allow_failure=true,
          (conn, _) => handle_nntp_connection(conn, node_id),
        ),
    )
    let gopher_addr = @socket.Addr::parse("\{host_addr}:\{gopher_port}")
    let gopher_srv = @socket.TcpServer::new(gopher_addr, reuse_addr=true)
    root.spawn_bg(
      allow_failure=true,
      () =>
        gopher_srv.run_forever(
          allow_failure=true,
          (conn, _) => handle_gopher_connection(conn, gopher_ctx),
        ),
    )
    let gmu_addr = @socket.Addr::parse("\{host_addr}:\{gmu_port}")
    root.spawn_bg(
      allow_failure=true,
      () =>
        run_gmu_server(gmu_addr, node_id, finger, fn(_plan) { () }),
    )
    root.spawn_bg(
      allow_failure=true,
      () =>
        run_discovery(
          node_id,
          finger,
          default_discovery_interval_ms,
          seed_peers,
          gmu_port,
        ),
    )
  })
}
