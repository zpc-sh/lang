///|
/// PgTap — Postgres wire protocol adapter for FlowTap.
///
/// Parses Postgres frontend/backend messages to extract structural
/// tokens. Only reads the 1-byte message type and 4-byte length.
/// Never parses query strings, parameter values, or row data.
///
/// Postgres wire format:
///   Frontend (client→server): [1] type | [4] length_be | [n] payload
///   Backend (server→client):  [1] type | [4] length_be | [n] payload
///   Startup message:          [4] length_be | [4] protocol_version | ...
///
/// Message types are single ASCII bytes:
///   Frontend: Q(Query), P(Parse), B(Bind), E(Execute), D(Describe),
///             S(Sync), C(Close), X(Terminate), H(Flush), p(password)
///   Backend:  C(CommandComplete), T(RowDescription), D(DataRow),
///             Z(ReadyForQuery), R(Authentication), K(BackendKeyData),
///             S(ParameterStatus), E(ErrorResponse), N(NoticeResponse),
///             1(ParseComplete), 2(BindComplete), 3(CloseComplete),
///             I(EmptyQueryResponse), G(CopyInResponse),
///             W(CopyBothResponse), d(CopyData), c(CopyDone)

// ---------------------------------------------------------------------------
// PgMessageType
// ---------------------------------------------------------------------------

///|
/// Postgres message types (structural, not content).
pub(all) enum PgMessageType {
  // Frontend messages
  Query // 'Q' (0x51)
  Parse // 'P' (0x50)
  Bind // 'B' (0x42)
  Execute // 'E' (0x45)
  Describe // 'D' (0x44)
  Sync // 'S' (0x53)
  Close // 'C' (0x43) — frontend Close
  Terminate // 'X' (0x58)
  FrontendFlush // 'H' (0x48)
  Password // 'p' (0x70)
  // Backend messages
  CommandComplete // 'C' (0x43) — backend CommandComplete
  RowDescription // 'T' (0x54)
  DataRow // 'D' (0x44) — backend DataRow
  ReadyForQuery // 'Z' (0x5A)
  Authentication // 'R' (0x52)
  BackendKeyData // 'K' (0x4B)
  ParameterStatus // 'S' (0x53) — backend ParameterStatus
  ErrorResponse // 'E' (0x45) — backend ErrorResponse
  NoticeResponse // 'N' (0x4E)
  ParseComplete // '1' (0x31)
  BindComplete // '2' (0x32)
  CloseComplete // '3' (0x33)
  EmptyQueryResp // 'I' (0x49)
  CopyInResponse // 'G' (0x47)
  CopyOutResponse // 'H' (0x48) — backend CopyOutResponse
  CopyData // 'd' (0x64)
  CopyDone // 'c' (0x63)
  Unknown(Int) // unrecognized type byte
} derive(Debug)

///|
/// Classify a frontend (client→server) message type byte.
pub fn pg_classify_frontend(type_byte : Int) -> PgMessageType {
  match type_byte {
    0x51 => Query // 'Q'
    0x50 => Parse // 'P'
    0x42 => Bind // 'B'
    0x45 => Execute // 'E'
    0x44 => Describe // 'D'
    0x53 => Sync // 'S'
    0x43 => Close // 'C'
    0x58 => Terminate // 'X'
    0x48 => FrontendFlush // 'H'
    0x70 => Password // 'p'
    other => Unknown(other)
  }
}

///|
/// Classify a backend (server→client) message type byte.
pub fn pg_classify_backend(type_byte : Int) -> PgMessageType {
  match type_byte {
    0x43 => CommandComplete // 'C'
    0x54 => RowDescription // 'T'
    0x44 => DataRow // 'D'
    0x5A => ReadyForQuery // 'Z'
    0x52 => Authentication // 'R'
    0x4B => BackendKeyData // 'K'
    0x53 => ParameterStatus // 'S'
    0x45 => ErrorResponse // 'E'
    0x4E => NoticeResponse // 'N'
    0x31 => ParseComplete // '1'
    0x32 => BindComplete // '2'
    0x33 => CloseComplete // '3'
    0x49 => EmptyQueryResp // 'I'
    0x47 => CopyInResponse // 'G'
    0x48 => CopyOutResponse // 'H'
    0x64 => CopyData // 'd'
    0x63 => CopyDone // 'c'
    other => Unknown(other)
  }
}

///|
/// Short token name for a PgMessageType.
fn pg_token_name(msg_type : PgMessageType) -> String {
  match msg_type {
    Query => "pg:Q"
    Parse => "pg:P"
    Bind => "pg:B"
    Execute => "pg:E"
    Describe => "pg:D"
    Sync => "pg:S"
    Close => "pg:Cf" // frontend Close
    Terminate => "pg:X"
    FrontendFlush => "pg:Hf" // frontend Flush
    Password => "pg:p"
    CommandComplete => "pg:C"
    RowDescription => "pg:T"
    DataRow => "pg:Dr" // backend DataRow
    ReadyForQuery => "pg:Z"
    Authentication => "pg:R"
    BackendKeyData => "pg:K"
    ParameterStatus => "pg:Sb" // backend ParameterStatus
    ErrorResponse => "pg:Eb" // backend ErrorResponse
    NoticeResponse => "pg:N"
    ParseComplete => "pg:1"
    BindComplete => "pg:2"
    CloseComplete => "pg:3"
    EmptyQueryResp => "pg:I"
    CopyInResponse => "pg:G"
    CopyOutResponse => "pg:Ho" // backend CopyOutResponse
    CopyData => "pg:d"
    CopyDone => "pg:c"
    Unknown(b) => "pg:?" + b.to_string()
  }
}

// ---------------------------------------------------------------------------
// PgTap
// ---------------------------------------------------------------------------

///|
/// Postgres wire protocol adapter wrapping a FlowTap.
pub(all) struct PgTap {
  flow_tap : @flow_tap.FlowTap
  mut last_fe : PgMessageType? // last frontend message
  mut last_be : PgMessageType? // last backend message
  mut fe_count : Int
  mut be_count : Int
} derive(Debug)

///|
pub fn PgTap::new(tap_id : String) -> PgTap {
  let config = @flow_tap.FlowTapConfig::default(tap_id, @flow_tap.Database)
  {
    flow_tap: @flow_tap.FlowTap::new(config),
    last_fe: None,
    last_be: None,
    fe_count: 0,
    be_count: 0,
  }
}

///|
/// Create with custom config.
pub fn PgTap::with_config(config : @flow_tap.FlowTapConfig) -> PgTap {
  {
    flow_tap: @flow_tap.FlowTap::new(config),
    last_fe: None,
    last_be: None,
    fe_count: 0,
    be_count: 0,
  }
}

///|
/// Observe a raw Postgres frame.
/// `is_frontend`: true if client→server, false if server→client.
/// `raw`: the raw frame bytes (type byte + length + payload).
/// `now_ms`: current timestamp in milliseconds.
///
/// Only reads:
///   - Byte 0: message type
///   - Bytes 1-4: message length (big-endian u32)
/// Does NOT read payload content.
pub fn PgTap::observe_raw(
  self : PgTap,
  is_frontend : Bool,
  raw : Array[Byte],
  now_ms : Int,
) -> Unit {
  if raw.length() < 5 {
    return
  } // too short to be a valid message

  let type_byte = raw[0].to_int()
  let msg_len = pg_read_u32_be(raw, 1)

  let direction : @flow_tap.FlowDirection = if is_frontend {
    @flow_tap.ClientToServer
  } else {
    @flow_tap.ServerToClient
  }

  let msg_type = if is_frontend {
    pg_classify_frontend(type_byte)
  } else {
    pg_classify_backend(type_byte)
  }

  // Track per-direction counts and last message types
  if is_frontend {
    self.fe_count = self.fe_count + 1
    self.last_fe = Some(msg_type)
  } else {
    self.be_count = self.be_count + 1
    self.last_be = Some(msg_type)
  }

  // Build the FlowFrame
  let frame : @flow_tap.FlowFrame = {
    direction,
    size_bytes: msg_len,
    type_tag: type_byte,
    has_body: msg_len > 4,
    timestamp_ms: now_ms,
  }

  self.flow_tap.observe(frame)
}

///|
/// Access the underlying FlowTap.
pub fn PgTap::tap(self : PgTap) -> @flow_tap.FlowTap {
  self.flow_tap
}

///|
/// Frontend message count.
pub fn PgTap::frontend_count(self : PgTap) -> Int {
  self.fe_count
}

///|
/// Backend message count.
pub fn PgTap::backend_count(self : PgTap) -> Int {
  self.be_count
}

// ---------------------------------------------------------------------------
// Frame builders (for testing)
// ---------------------------------------------------------------------------

///|
/// Build a synthetic Postgres frontend message frame.
/// Returns [type_byte, len_be(4), ...padding].
pub fn pg_build_frame(type_byte : Int, payload_len : Int) -> Array[Byte] {
  let frame : Array[Byte] = []
  frame.push(type_byte.to_byte())
  let total_len = payload_len + 4 // length includes itself
  frame.push(((total_len >> 24) & 0xFF).to_byte())
  frame.push(((total_len >> 16) & 0xFF).to_byte())
  frame.push(((total_len >> 8) & 0xFF).to_byte())
  frame.push((total_len & 0xFF).to_byte())
  // Payload padding (just zeros — we don't read content)
  let mut i = 0
  while i < payload_len {
    frame.push(b'\x00')
    i = i + 1
  }
  frame
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

///|
fn pg_read_u32_be(data : Array[Byte], pos : Int) -> Int {
  ((data[pos].to_int() & 0xFF) << 24) |
  ((data[pos + 1].to_int() & 0xFF) << 16) |
  ((data[pos + 2].to_int() & 0xFF) << 8) |
  (data[pos + 3].to_int() & 0xFF)
}
