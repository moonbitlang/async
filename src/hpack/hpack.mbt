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

///|
/// HPACK encoder.
struct Encoder {
  dynamic_table : DynamicTable
  huffman : Bool
}

///|
/// HPACK decoder.
struct Decoder {
  dynamic_table : DynamicTable
}

///|
/// Headers that should use literal without indexing (sensitive).
let sensitive_headers : Array[String] = [
  "cookie", "authorization", "set-cookie",
]

///|
/// Check if a header name is sensitive.
fn is_sensitive(name : String) -> Bool {
  for i = 0; i < sensitive_headers.length(); i = i + 1 {
    if sensitive_headers[i] == name {
      return true
    }
  }
  false
}

// --- Integer encoding/decoding (RFC 7541 Section 5.1) ---

///|
/// Encode an integer with the given prefix bits.
/// prefix_byte contains the non-prefix bits already set in the high bits.
fn encode_integer(
  buf : @buffer.Buffer,
  value : Int,
  prefix_bits : Int,
  prefix_byte : Byte,
) -> Unit {
  let max_prefix = (1 << prefix_bits) - 1
  if value < max_prefix {
    buf.write_byte((prefix_byte.to_int() | value).to_byte())
  } else {
    buf.write_byte((prefix_byte.to_int() | max_prefix).to_byte())
    let mut v = value - max_prefix
    while v >= 128 {
      buf.write_byte((v % 128 + 128).to_byte())
      v = v / 128
    }
    buf.write_byte(v.to_byte())
  }
}

///|
/// Decode an integer with the given prefix bits from data at offset.
/// Returns (value, new_offset).
fn decode_integer(
  data : Bytes,
  offset : Int,
  prefix_bits : Int,
) -> (Int, Int) raise {
  guard offset < data.length() else {
    raise Failure::Failure("decode_integer: unexpected end of data")
  }
  let max_prefix = (1 << prefix_bits) - 1
  let mut value = data[offset].to_int() & max_prefix
  let mut pos = offset + 1
  if value < max_prefix {
    return (value, pos)
  }
  let mut m = 0
  for {
    guard pos < data.length() else {
      raise Failure::Failure(
        "decode_integer: unexpected end of data in continuation",
      )
    }
    let b = data[pos].to_int()
    pos = pos + 1
    value = value + ((b & 127) << m)
    m = m + 7
    if (b & 128) == 0 {
      break
    }
  }
  (value, pos)
}

// --- String encoding/decoding (RFC 7541 Section 5.2) ---

///|
/// Encode a string literal. If huffman is true, use Huffman encoding.
fn encode_string(buf : @buffer.Buffer, s : String, huffman : Bool) -> Unit {
  let raw = string_to_bytes(s)
  if huffman {
    let encoded = huffman_encode(raw)
    encode_integer(buf, encoded.length(), 7, b'\x80')
    buf.write_bytes(encoded)
  } else {
    encode_integer(buf, raw.length(), 7, b'\x00')
    buf.write_bytes(raw)
  }
}

///|
/// Decode a string literal from data at offset.
/// Returns (string, new_offset).
fn decode_string(data : Bytes, offset : Int) -> (String, Int) raise {
  guard offset < data.length() else {
    raise Failure::Failure("decode_string: unexpected end of data")
  }
  let is_huffman = (data[offset].to_int() & 0x80) != 0
  let (str_len, pos) = decode_integer(data, offset, 7)
  guard pos + str_len <= data.length() else {
    raise Failure::Failure("decode_string: string length exceeds data")
  }
  let raw = bytes_slice(data, pos, str_len)
  let s = if is_huffman {
    let decoded = huffman_decode(raw)
    bytes_to_string(decoded)
  } else {
    bytes_to_string(raw)
  }
  (s, pos + str_len)
}

// --- Helper functions for string <-> bytes conversion ---

///|
/// Convert a String to Bytes (UTF-8 encoding).
fn string_to_bytes(s : String) -> Bytes {
  let buf = @buffer.new()
  for i = 0; i < s.length(); i = i + 1 {
    let c = s[i]
    let code = c.to_int()
    if code < 0x80 {
      buf.write_byte(code.to_byte())
    } else if code < 0x800 {
      buf.write_byte((0xC0 | (code >> 6)).to_byte())
      buf.write_byte((0x80 | (code & 0x3F)).to_byte())
    } else if code < 0x10000 {
      buf.write_byte((0xE0 | (code >> 12)).to_byte())
      buf.write_byte((0x80 | ((code >> 6) & 0x3F)).to_byte())
      buf.write_byte((0x80 | (code & 0x3F)).to_byte())
    } else {
      buf.write_byte((0xF0 | (code >> 18)).to_byte())
      buf.write_byte((0x80 | ((code >> 12) & 0x3F)).to_byte())
      buf.write_byte((0x80 | ((code >> 6) & 0x3F)).to_byte())
      buf.write_byte((0x80 | (code & 0x3F)).to_byte())
    }
  }
  buf.contents()
}

///|
/// Convert Bytes (UTF-8) to a String.
fn bytes_to_string(b : Bytes) -> String {
  let arr : Array[Char] = []
  let mut i = 0
  while i < b.length() {
    let byte0 = b[i].to_int()
    if byte0 < 0x80 {
      arr.push(byte0.unsafe_to_char())
      i = i + 1
    } else if (byte0 & 0xE0) == 0xC0 {
      let code = ((byte0 & 0x1F) << 6) | (b[i + 1].to_int() & 0x3F)
      arr.push(code.unsafe_to_char())
      i = i + 2
    } else if (byte0 & 0xF0) == 0xE0 {
      let code = ((byte0 & 0x0F) << 12) |
        ((b[i + 1].to_int() & 0x3F) << 6) |
        (b[i + 2].to_int() & 0x3F)
      arr.push(code.unsafe_to_char())
      i = i + 3
    } else {
      let code = ((byte0 & 0x07) << 18) |
        ((b[i + 1].to_int() & 0x3F) << 12) |
        ((b[i + 2].to_int() & 0x3F) << 6) |
        (b[i + 3].to_int() & 0x3F)
      arr.push(code.unsafe_to_char())
      i = i + 4
    }
  }
  String::from_array(arr)
}

///|
/// Extract a slice of bytes.
fn bytes_slice(data : Bytes, offset : Int, length : Int) -> Bytes {
  data[offset:offset + length].to_bytes()
}

// --- Encoder ---

///|
/// Create a new HPACK encoder.
pub fn Encoder::new(
  max_table_size? : Int = 4096,
  huffman? : Bool = true,
) -> Encoder {
  { dynamic_table: DynamicTable::new(max_size=max_table_size), huffman }
}

///|
/// Look up a header in the static and dynamic tables.
/// Returns (index, has_value_match).
fn Encoder::find_header(
  self : Encoder,
  name : String,
  value : String,
) -> (Int, Bool) {
  // Check static table first for exact (name, value) match
  match static_table_by_name_value.get(name) {
    Some(value_map) =>
      match value_map.get(value) {
        Some(index) => return (index, true)
        None => ()
      }
    None => ()
  }
  // Check dynamic table for exact match
  for i = 0; i < self.dynamic_table.length(); i = i + 1 {
    match self.dynamic_table.get(i) {
      Some((n, v)) =>
        if n == name && v == value {
          return (static_table.length() + 1 + i, true)
        }
      None => ()
    }
  }
  // Check static table for name-only match
  match static_table_by_name.get(name) {
    Some(index) => return (index, false)
    None => ()
  }
  // Check dynamic table for name-only match
  for i = 0; i < self.dynamic_table.length(); i = i + 1 {
    match self.dynamic_table.get(i) {
      Some((n, _)) =>
        if n == name {
          return (static_table.length() + 1 + i, false)
        }
      None => ()
    }
  }
  (0, false)
}

///|
/// Encode a list of headers into an HPACK header block.
pub fn Encoder::encode(
  self : Encoder,
  headers : Array[(String, String)],
) -> Bytes {
  let buf = @buffer.new()
  for i = 0; i < headers.length(); i = i + 1 {
    let (name, value) = headers[i]
    let (index, value_match) = self.find_header(name, value)
    if index > 0 && value_match {
      // Indexed header field representation (Section 6.1)
      encode_integer(buf, index, 7, b'\x80')
    } else if is_sensitive(name) {
      // Literal header field without indexing (Section 6.2.2)
      if index > 0 {
        encode_integer(buf, index, 4, b'\x00')
      } else {
        buf.write_byte(b'\x00')
        encode_string(buf, name, self.huffman)
      }
      encode_string(buf, value, self.huffman)
    } else {
      // Literal header field with incremental indexing (Section 6.2.1)
      if index > 0 {
        encode_integer(buf, index, 6, b'\x40')
      } else {
        buf.write_byte(b'\x40')
        encode_string(buf, name, self.huffman)
      }
      encode_string(buf, value, self.huffman)
      self.dynamic_table.add(name, value)
    }
  }
  buf.contents()
}

// --- Decoder ---

///|
/// Create a new HPACK decoder.
pub fn Decoder::new(max_table_size? : Int = 4096) -> Decoder {
  { dynamic_table: DynamicTable::new(max_size=max_table_size) }
}

///|
/// Look up a header by HPACK index (1-based).
fn Decoder::lookup(self : Decoder, index : Int) -> (String, String) raise {
  if index < 1 {
    raise Failure::Failure("hpack: invalid index 0")
  }
  if index <= static_table.length() {
    return static_table[index - 1]
  }
  let dyn_index = index - static_table.length() - 1
  match self.dynamic_table.get(dyn_index) {
    Some(entry) => entry
    None =>
      raise Failure::Failure(
        "hpack: dynamic table index out of range: \{index}",
      )
  }
}

///|
/// Decode an HPACK header block into a list of headers.
pub fn Decoder::decode(
  self : Decoder,
  data : Bytes,
) -> Array[(String, String)] raise {
  let headers : Array[(String, String)] = []
  let mut pos = 0
  while pos < data.length() {
    let byte0 = data[pos].to_int()
    if (byte0 & 0x80) != 0 {
      // Indexed header field representation (Section 6.1)
      let (index, new_pos) = decode_integer(data, pos, 7)
      pos = new_pos
      if index == 0 {
        raise Failure::Failure("hpack: indexed header with index 0")
      }
      let entry = self.lookup(index)
      headers.push(entry)
    } else if (byte0 & 0xC0) == 0x40 {
      // Literal header field with incremental indexing (Section 6.2.1)
      let (index, new_pos) = decode_integer(data, pos, 6)
      pos = new_pos
      let name = if index > 0 {
        let (n, _) = self.lookup(index)
        n
      } else {
        let (n, new_pos2) = decode_string(data, pos)
        pos = new_pos2
        n
      }
      let (value, new_pos3) = decode_string(data, pos)
      pos = new_pos3
      self.dynamic_table.add(name, value)
      headers.push((name, value))
    } else if (byte0 & 0xF0) == 0x00 {
      // Literal header field without indexing (Section 6.2.2)
      let (index, new_pos) = decode_integer(data, pos, 4)
      pos = new_pos
      let name = if index > 0 {
        let (n, _) = self.lookup(index)
        n
      } else {
        let (n, new_pos2) = decode_string(data, pos)
        pos = new_pos2
        n
      }
      let (value, new_pos3) = decode_string(data, pos)
      pos = new_pos3
      headers.push((name, value))
    } else if (byte0 & 0xF0) == 0x10 {
      // Literal header field never indexed (Section 6.2.3)
      let (index, new_pos) = decode_integer(data, pos, 4)
      pos = new_pos
      let name = if index > 0 {
        let (n, _) = self.lookup(index)
        n
      } else {
        let (n, new_pos2) = decode_string(data, pos)
        pos = new_pos2
        n
      }
      let (value, new_pos3) = decode_string(data, pos)
      pos = new_pos3
      headers.push((name, value))
    } else if (byte0 & 0xE0) == 0x20 {
      // Dynamic table size update (Section 6.3)
      let (new_size, new_pos) = decode_integer(data, pos, 5)
      pos = new_pos
      self.dynamic_table.set_max_size(new_size)
    } else {
      raise Failure::Failure("hpack: unknown header field representation")
    }
  }
  headers
}
