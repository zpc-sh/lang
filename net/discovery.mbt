///|
/// Periodic peer discovery loop.
///
/// Sends GMU/1 PlanRequest to all known seed peers on each interval.
/// PlanResponse handling is done in gmu_server.mbt via the on_plan callback.
pub let default_discovery_interval_ms : Int = 30000

///|
/// Run the discovery loop.
///
/// `seeds` is the initial list of "host:port" strings to ping.
/// Runs forever inside the caller's task group.
pub async fn run_discovery(
  node_id : String,
  finger : @finger.FingerState,
  interval_ms : Int,
  seeds : Array[String],
  gmu_port : Int,
) -> Unit {
  let effective_ms = if interval_ms > 0 {
    interval_ms
  } else {
    default_discovery_interval_ms
  }
  for ;; {
    @async.sleep(effective_ms)
    ping_seeds(node_id, finger, seeds)
    ping_peers_from_plans(node_id, finger, gmu_port)
  }
}

// ---------------------------------------------------------------------------
// Ping helpers
// ---------------------------------------------------------------------------

///|
async fn ping_seeds(
  node_id : String,
  finger : @finger.FingerState,
  seeds : Array[String],
) -> Unit {
  let seq = finger.next_sequence()
  let msg = @finger.GmuMessage::plan_request(node_id, "", seq)
  for addr_str in seeds {
    match parse_addr_safe(addr_str) {
      None => ()
      Some(addr) => send_gmu(addr, msg)
    }
  }
}

///|
async fn ping_peers_from_plans(
  node_id : String,
  finger : @finger.FingerState,
  gmu_port : Int,
) -> Unit {
  let seq = finger.next_sequence()
  let msg = @finger.GmuMessage::plan_request(node_id, "", seq)
  for peer in finger.known_peers {
    match peer.plan {
      None => ()
      Some(plan) =>
        for endpoint in plan.endpoints {
          // endpoints may be host:port or just host — append gmu_port if no port
          let addr_str = if endpoint.contains(":") {
            endpoint
          } else {
            "\{endpoint}:\{gmu_port}"
          }
          match parse_addr_safe(addr_str) {
            None => ()
            Some(addr) => send_gmu(addr, msg)
          }
        }
    }
  }
}

///|
fn parse_addr_safe(s : String) -> @socket.Addr? {
  Some(@socket.Addr::parse(s)) catch {
    _ => None
  }
}
