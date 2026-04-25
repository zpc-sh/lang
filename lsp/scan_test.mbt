///|
test "scan clean ASCII is clean" {
  let r = scan_str("hello world")
  assert_true(r.clean)
  assert_eq(r.hits.length(), 0)
  assert_false(r.newline_mixed)
  assert_false(r.quote_mixed)
  assert_false(r.has_bidi)
}

///|
test "scan detects CRLF" {
  let data : Array[Byte] = [0x68, 0x69, 0x0D, 0x0A] // "hi\r\n"
  let r = scan_bytes(data)
  assert_false(r.clean)
  assert_eq(r.hits.length(), 1)
  assert_eq(r.hits[0].kind, CrlfNewline)
  assert_eq(r.hits[0].offset, 2)
}

///|
test "scan detects bare CR" {
  let data : Array[Byte] = [0x68, 0x0D, 0x69] // "h\ri"
  let r = scan_bytes(data)
  assert_false(r.clean)
  assert_eq(r.hits[0].kind, BareCarriage)
}

///|
test "scan detects mixed newlines CRLF+LF" {
  // "line1\r\nline2\n"
  let data : Array[Byte] = [
    0x61, 0x0D, 0x0A, 0x62, 0x0A,
  ]
  let r = scan_bytes(data)
  assert_true(r.newline_mixed)
}

///|
test "scan detects BiDi RLO U+202E" {
  // UTF-8 encoding of U+202E: E2 80 AE
  let data : Array[Byte] = [0x61, 0xE2, 0x80, 0xAE, 0x62]
  let r = scan_bytes(data)
  assert_false(r.clean)
  assert_true(r.has_bidi)
  assert_eq(r.hits[0].kind, BiDiControl)
  assert_eq(r.hits[0].cp, 0x202E)
  assert_eq(r.hits[0].offset, 1)
}

///|
test "scan detects BiDi LRI U+2066" {
  // UTF-8 of U+2066: E2 81 A6
  let data : Array[Byte] = [0xE2, 0x81, 0xA6, 0x78]
  let r = scan_bytes(data)
  assert_true(r.has_bidi)
  assert_eq(r.hits[0].kind, BiDiIsolate)
  assert_eq(r.hits[0].cp, 0x2066)
}

///|
test "scan detects curly left double quote U+201C" {
  // UTF-8 of U+201C: E2 80 9C
  let data : Array[Byte] = [0x61, 0xE2, 0x80, 0x9C, 0x62]
  let r = scan_bytes(data)
  assert_false(r.clean)
  assert_eq(r.hits[0].kind, CurlyQuote)
  assert_eq(r.hits[0].cp, 0x201C)
}

///|
test "scan detects quote mixing: ASCII + curly" {
  // 'hello' with curly single quotes around ASCII apostrophe inside
  // U+2018 = E2 80 98,  U+2019 = E2 80 99
  let data : Array[Byte] = [
    0xE2, 0x80, 0x98, // U+2018 left single curly
    0x69, 0x74, 0x27, // it'
    0xE2, 0x80, 0x99, // U+2019 right single curly
  ]
  let r = scan_bytes(data)
  assert_true(r.quote_mixed)
}

///|
test "scan detects zero-width space U+200B" {
  // UTF-8 of U+200B: E2 80 8B
  let data : Array[Byte] = [0x61, 0xE2, 0x80, 0x8B, 0x62]
  let r = scan_bytes(data)
  assert_eq(r.hits[0].kind, ZeroWidth)
  assert_eq(r.hits[0].cp, 0x200B)
}

///|
test "scan detects soft hyphen U+00AD" {
  // UTF-8 of U+00AD: C2 AD
  let data : Array[Byte] = [0x61, 0xC2, 0xAD, 0x62]
  let r = scan_bytes(data)
  assert_eq(r.hits[0].kind, SoftHyphen)
  assert_eq(r.hits[0].cp, 0x00AD)
}

///|
test "scan detects invalid UTF-8 sequence" {
  // 0xFF is never valid in UTF-8
  let data : Array[Byte] = [0x61, 0xFF, 0x62]
  let r = scan_bytes(data)
  assert_eq(r.hits[0].kind, InvalidUtf8)
  assert_eq(r.hits[0].offset, 1)
}

///|
test "scan detects line separator U+2028" {
  // UTF-8 of U+2028: E2 80 A8
  let data : Array[Byte] = [0x61, 0xE2, 0x80, 0xA8, 0x62]
  let r = scan_bytes(data)
  assert_eq(r.hits[0].kind, LineSeparator)
  assert_eq(r.hits[0].cp, 0x2028)
}

///|
test "scan detects fullwidth quotation mark U+FF02" {
  // UTF-8 of U+FF02: EF BC 82
  let data : Array[Byte] = [0x61, 0xEF, 0xBC, 0x82, 0x62]
  let r = scan_bytes(data)
  assert_eq(r.hits[0].kind, FullwidthQuote)
  assert_eq(r.hits[0].cp, 0xFF02)
}

///|
test "scan_str convenience wrapper" {
  let r = scan_str("clean text")
  assert_true(r.clean)
  assert_eq(r.summary(), "clean")
}

///|
test "summary reports hit count and flags" {
  // Two CRLF hits
  let data : Array[Byte] = [0x61, 0x0D, 0x0A, 0x62, 0x0A, 0x63, 0x0D, 0x0A]
  let r = scan_bytes(data)
  assert_true(r.newline_mixed)
  let s = r.summary()
  assert_true(s.has_prefix("2 hit"))
  // summary must mention newline-mixed flag
  assert_true(s != "clean")
}

///|
test "counts groups hits by kind" {
  let data : Array[Byte] = [
    0x61, 0x0D, 0x0A, // CRLF
    0x62, 0x0D, 0x0A, // CRLF
    0xE2, 0x80, 0xAE, // BiDi RLO
  ]
  let r = scan_bytes(data)
  let c = r.counts()
  // Should have CrlfNewline:2, BiDiControl:1
  let mut got_crlf = false
  let mut got_bidi = false
  for pair in c {
    if pair.0 == CrlfNewline && pair.1 == 2 {
      got_crlf = true
    }
    if pair.0 == BiDiControl && pair.1 == 1 {
      got_bidi = true
    }
  }
  assert_true(got_crlf)
  assert_true(got_bidi)
}
