///|
/// Crypto — thin wrapper over HostBridge crypto primitives.
///
/// The host provides real implementations (SHA-256/BLAKE3, ed25519).
/// The stub falls back to FNV-1a hash and no-op sign/verify.

// ---------------------------------------------------------------------------
// Hash
// ---------------------------------------------------------------------------

///|
/// Hash `data` using the host's hash primitive.
pub fn crypto_hash(host : @node.HostBridge, data : Array[Byte]) -> Array[Byte] {
  (host.crypto_hash)(data)
}

///|
/// Hex-encoded hash of `data`.
pub fn crypto_hash_hex(host : @node.HostBridge, data : Array[Byte]) -> String {
  let bytes = (host.crypto_hash)(data)
  let sb = StringBuilder::new()
  for b in bytes {
    sb.write_char(hex_nibble((b.to_int() >> 4) & 0xF))
    sb.write_char(hex_nibble(b.to_int() & 0xF))
  }
  sb.to_string()
}

// ---------------------------------------------------------------------------
// Sign / verify
// ---------------------------------------------------------------------------

///|
/// Sign `msg` with a 64-byte ed25519 private key.
pub fn crypto_sign(
  host : @node.HostBridge,
  msg : Array[Byte],
  private_key : Array[Byte],
) -> Array[Byte] {
  (host.crypto_sign)(msg, private_key)
}

///|
/// Verify a 64-byte ed25519 signature.
pub fn crypto_verify(
  host : @node.HostBridge,
  msg : Array[Byte],
  signature : Array[Byte],
  public_key : Array[Byte],
) -> Bool {
  (host.crypto_verify)(msg, signature, public_key)
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

///|
fn hex_nibble(n : Int) -> Char {
  match n {
    0 => '0'
    1 => '1'
    2 => '2'
    3 => '3'
    4 => '4'
    5 => '5'
    6 => '6'
    7 => '7'
    8 => '8'
    9 => '9'
    10 => 'a'
    11 => 'b'
    12 => 'c'
    13 => 'd'
    14 => 'e'
    _ => 'f'
  }
}
