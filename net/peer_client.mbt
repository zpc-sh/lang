///|
/// Outbound peer operations — one-shot async connections.

// ---------------------------------------------------------------------------
// NNTP client
// ---------------------------------------------------------------------------

///|
/// Post one article to a peer's NNTP port.
pub async fn connect_and_post_nntp(
  peer_addr : @socket.Addr,
  article : @nntp.NntpArticle,
) -> Unit {
  let conn = @socket.Tcp::connect(peer_addr)
  defer conn.close()
  let _ = conn.read_until("\r\n") // discard banner
  conn.write(Bytes::from_array(@nntp.build_group_command(article.newsgroup)[:]))
  let _ = conn.read_until("\r\n")
  conn.write(Bytes::from_array(@nntp.build_post_preamble()[:]))
  let _ = conn.read_until("\r\n") // "340 send article"
  conn.write(Bytes::from_array(article.to_wire()[:]))
  conn.write(Bytes::from_array(@nntp.post_terminator()[:]))
  let _ = conn.read_until("\r\n") // result
  conn.write(Bytes::from_array(@nntp.build_quit()[:]))
}

///|
/// Fetch an OCI layer by CAS hash from a peer's NNTP port.
pub async fn fetch_oci_layer(
  peer_addr : @socket.Addr,
  hash : String,
) -> Array[Byte]? {
  let conn = @socket.Tcp::connect(peer_addr)
  defer conn.close()
  let _ = conn.read_until("\r\n") // banner
  conn.write(
    Bytes::from_array(@nntp.build_group_command(@nntp.ng_oci_layer)[:]),
  )
  let _ = conn.read_until("\r\n")
  conn.write(Bytes::from_array(@nntp.build_article_request(hash)[:]))
  let buf = collect_until_dot_crlf(conn)
  conn.write(Bytes::from_array(@nntp.build_quit()[:]))
  match @nntp.NntpArticle::from_wire(buf) {
    None => None
    Some(article) => Some(article.payload)
  }
}

// ---------------------------------------------------------------------------
// Gopher client
// ---------------------------------------------------------------------------

///|
/// Fetch raw capability response bytes from a peer's Gopher port.
pub async fn fetch_gopher_caps(peer_addr : @socket.Addr) -> Array[Byte]? {
  let bytes = gopher_fetch(peer_addr, "/caps")
  if bytes.is_empty() {
    None
  } else {
    Some(bytes)
  }
}

///|
/// Fetch a WASM binary from a peer via Gopher.
pub async fn fetch_gopher_wasm(
  peer_addr : @socket.Addr,
  selector : String,
) -> Array[Byte]? {
  let bytes = gopher_fetch(peer_addr, selector)
  if bytes.is_empty() {
    None
  } else {
    Some(bytes)
  }
}

///|
async fn gopher_fetch(
  peer_addr : @socket.Addr,
  selector : String,
) -> Array[Byte] {
  let conn = @socket.Tcp::connect(peer_addr)
  defer conn.close()
  conn.write(Bytes::of_string("\{selector}\r\n"))
  collect_all(conn)
}

// ---------------------------------------------------------------------------
// GMU/1 client
// ---------------------------------------------------------------------------

///|
/// Send a GMU/1 message to a peer (fire-and-forget UDP).
pub async fn send_gmu(
  peer_addr : @socket.Addr,
  msg : @finger.GmuMessage,
) -> Unit {
  let client = @socket.UdpClient::new(peer_addr)
  defer client.close()
  client.send(Bytes::from_array(msg.encode()[:]))
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

///|
async fn collect_all(conn : @socket.Tcp) -> Array[Byte] {
  let buf : Array[Byte] = []
  for ;; {
    match conn.read_some() {
      None => break
      Some(chunk) =>
        for b in chunk {
          buf.push(b)
        }
    }
  }
  buf
}

///|
async fn collect_until_dot_crlf(conn : @socket.Tcp) -> Array[Byte] {
  let buf : Array[Byte] = []
  for ;; {
    match conn.read_some() {
      None => break
      Some(chunk) => {
        for b in chunk {
          buf.push(b)
        }
        if ends_with_dot_crlf(buf) {
          break
        }
      }
    }
  }
  buf
}

///|
fn ends_with_dot_crlf(buf : Array[Byte]) -> Bool {
  let n = buf.length()
  n >= 5 &&
  buf[n - 5] == b'\r' &&
  buf[n - 4] == b'\n' &&
  buf[n - 3] == b'.' &&
  buf[n - 2] == b'\r' &&
  buf[n - 1] == b'\n'
}
