///|
/// GMU/1 UDP server — peer messaging listener.
///
/// Receives datagrams, decodes, dispatches responses.

let gmu_max_datagram : Int = 65507

///|
pub async fn run_gmu_server(
  addr : @socket.Addr,
  node_id : String,
  finger : @finger.FingerState,
  on_plan : (@finger.FingerPlan) -> Unit,
) -> Unit {
  let server = @socket.UdpServer::new(addr)
  defer server.close()
  let buf = FixedArray::make(gmu_max_datagram, b'\x00')
  for ;; {
    let (n, src_addr) = server.recvfrom(buf)
    if n == 0 {
      continue
    }
    let data = buf.unsafe_reinterpret_as_bytes()[0:n].to_bytes().iter().collect()
    match @finger.GmuMessage::decode(data) {
      None => ()
      Some(msg) =>
        handle_gmu_message(server, src_addr, msg, node_id, finger, on_plan)
    }
  }
}

async fn handle_gmu_message(
  server : @socket.UdpServer,
  src : @socket.Addr,
  msg : @finger.GmuMessage,
  node_id : String,
  finger : @finger.FingerState,
  on_plan : (@finger.FingerPlan) -> Unit,
) -> Unit {
  match msg.msg_type {
    @finger.GmuType::Ping => {
      let pong = @finger.GmuMessage::pong(node_id, msg.sequence)
      server.sendto(Bytes::from_array(pong.encode()[:]), src)
      finger.note_peer(msg.source, 0)
    }
    @finger.GmuType::Pong => finger.note_peer(msg.source, 0)
    @finger.GmuType::PlanRequest => {
      let plan = @finger.FingerPlan::generate(
        node_id, 0, "standard", "lang", "standard", "Headless", [], 0, [], 0,
      )
      let response = @finger.GmuMessage::new(
        @finger.GmuType::PlanResponse, 0, node_id, msg.source, plan.to_bytes(),
      )
      server.sendto(Bytes::from_array(response.encode()[:]), src)
    }
    @finger.GmuType::PlanResponse =>
      match @finger.FingerPlan::from_bytes(msg.payload) {
        None => ()
        Some(plan) => {
          finger.note_peer(msg.source, plan.timestamp)
          finger.update_peer_plan(msg.source, plan)
          on_plan(plan)
        }
      }
    _ => ()
  }
}
