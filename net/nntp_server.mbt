///|
/// NNTP per-connection handler.
///
/// Each accepted TCP connection gets its own NntpState.  Sends the greeting
/// banner, then drives the codec until the client disconnects or sends QUIT.

///|
pub async fn handle_nntp_connection(
  conn : @socket.Tcp,
  node_id : String,
) -> Unit {
  defer conn.close()
  let state = @nntp.NntpState::new(node_id)
  conn.write(Bytes::from_array(state.greeting()[:]))
  for ;; {
    match conn.read_some() {
      None => break
      Some(chunk) => {
        let bytes = chunk.iter().collect()
        let response = state.handle_bytes(bytes)
        if response.length() > 0 {
          conn.write(Bytes::from_array(response[:]))
        }
        if is_quit_response(response) {
          break
        }
      }
    }
  }
}

fn is_quit_response(response : Array[Byte]) -> Bool {
  response.length() >= 3 &&
  response[0] == b'2' &&
  response[1] == b'0' &&
  response[2] == b'5'
}
