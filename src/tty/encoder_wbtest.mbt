// Copyright 2025 International Digital Economy Academy
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

// Tests for the Windows console record encoder.
// It works on the raw 20-byte `INPUT_RECORD` layout, so these run everywhere.

///|
/// A 20-byte `INPUT_RECORD` with `EventType = kind`,
/// the 32-bit field at offset 4 set to `field`
/// and, for key events, `wVirtualKeyCode = key` and `uChar.UnicodeChar = char`.
fn record(
  kind : Int32,
  field : Int32,
  key~ : Int32 = 0,
  char~ : Int32 = 0,
) -> Array[Byte] {
  let rec = Array::make(20, b'\x00')
  rec[0] = (kind & 0xFF).to_byte()
  rec[1] = ((kind >> 8) & 0xFF).to_byte()
  for i in 0..<4 {
    rec[4 + i] = ((field >> (8 * i)) & 0xFF).to_byte()
  }
  // wRepeatCount
  rec[8] = b'\x01'
  rec[10] = (key & 0xFF).to_byte()
  rec[11] = ((key >> 8) & 0xFF).to_byte()
  rec[14] = (char & 0xFF).to_byte()
  rec[15] = ((char >> 8) & 0xFF).to_byte()
  rec
}

///|
fn key_down(char : Int32) -> Array[Byte] {
  record(0x1, 1, char~)
}

///|
fn key_up(char : Int32) -> Array[Byte] {
  record(0x1, 0, char~)
}

///|
/// `VK_MENU`, which carries characters entered with Alt+Numpad on key up.
fn alt(down : Bool, char~ : Int32 = 0) -> Array[Byte] {
  record(0x1, if down { 1 } else { 0 }, key=0x12, char~)
}

///|
fn focus(gained : Bool) -> Array[Byte] {
  record(0x10, if gained { 1 } else { 0 })
}

///|
/// `WINDOW_BUFFER_SIZE_EVENT`, `dwSize` is a `COORD { X = cols, Y = rows }`.
fn buffer_size(rows : Int32, cols : Int32) -> Array[Byte] {
  record(0x4, cols | (rows << 16))
}

///|
fn mouse() -> Array[Byte] {
  record(0x2, 0)
}

///|
fn encode(
  enc : @event_loop.TtyEncoder,
  records : Array[Array[Byte]],
  rows~ : Int32 = 24,
  cols~ : Int32 = 80,
  len~ : Int32 = 64,
) -> (Bytes, Bool) {
  let flat = []
  for rec in records {
    flat.append(rec)
  }
  let buf = FixedArray::make(len, b'\x00')
  let (n, resized) = enc.encode(Bytes::from_array(flat), rows~, cols~, buf)
  (Bytes::from_array(buf[:n]), resized)
}

///|
fn with_encoder(f : (@event_loop.TtyEncoder) -> Unit raise) -> Unit raise {
  let enc = @event_loop.TtyEncoder::new(24, 80)
  defer enc.free()
  f(enc)
}

///|
test "encoder: characters become UTF-8" {
  with_encoder(enc => {
    let records = [key_down('a'), key_up('a'), key_down(0xE9), key_down(0x4E2D)]
    assert_eq(encode(enc, records), (b"a\xc3\xa9\xe4\xb8\xad", false))
  })
}

///|
test "encoder: surrogate pair split across batches" {
  with_encoder(enc => {
    assert_eq(encode(enc, [key_down(0xD83D)]), (b"", false))
    assert_eq(encode(enc, [key_down(0xDE00)]), (b"\xf0\x9f\x98\x80", false))
  })
}

///|
test "encoder: unpaired surrogates" {
  with_encoder(enc => {
    // an unpaired high surrogate is dropped
    assert_eq(encode(enc, [key_down(0xD83D), key_down('x')]), (b"x", false))
    // an unpaired low surrogate becomes U+FFFD
    assert_eq(encode(enc, [key_down(0xDE00)]), (b"\xef\xbf\xbd", false))
  })
}

///|
test "encoder: characters on Alt key up" {
  with_encoder(enc => {
    // what ConPTY sends for U+1F600
    let records = [
      alt(true),
      alt(false, char=0xD83D),
      alt(true),
      alt(false, char=0xDE00),
    ]
    assert_eq(encode(enc, records), (b"\xf0\x9f\x98\x80", false))
    // a plain Alt press produces nothing
    assert_eq(encode(enc, [alt(true), alt(false)]), (b"", false))
  })
}

///|
test "encoder: dropped records" {
  with_encoder(enc => {
    let records = [key_down(0), key_up('b'), mouse(), buffer_size(9000, 80)]
    assert_eq(encode(enc, records), (b"", false))
  })
}

///|
test "encoder: focus" {
  with_encoder(enc => {
    let records = [focus(true), focus(false)]
    assert_eq(encode(enc, records), (b"\x1b[I\x1b[O", false))
  })
}

///|
test "encoder: resize is reported once per change" {
  with_encoder(enc => {
    assert_eq(encode(enc, [], rows=24, cols=80), (b"", false))
    assert_eq(
      encode(enc, [buffer_size(30, 100)], rows=30, cols=100),
      (b"", true),
    )
    assert_eq(encode(enc, [key_down('k')], rows=30, cols=100), (b"k", false))
    // a resize without a record of its own is reported with the next input
    assert_eq(encode(enc, [key_down('k')], rows=30, cols=90), (b"k", true))
    // an unknown size is ignored
    assert_eq(encode(enc, [], rows=0, cols=0), (b"", false))
  })
}

///|
test "encoder: bytes that do not fit are kept for the next call" {
  with_encoder(enc => {
    assert_eq(encode(enc, [key_down(0x4E2D)], len=2), (b"\xe4\xb8", false))
    assert_eq(encode(enc, [], len=2), (b"\xad", false))
    assert_eq(encode(enc, [], len=2), (b"", false))
  })
}
