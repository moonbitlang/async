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

// --- Integer encoding/decoding tests ---

///|
test "integer encode/decode round-trip small value" {
  let buf = @buffer.new()
  encode_integer(buf, 10, 5, b'\x00')
  let data = buf.contents()
  let (value, offset) = decode_integer(data, 0, 5)
  inspect(value, content="10")
  inspect(offset, content="1")
}

///|
test "integer encode/decode round-trip large value" {
  let buf = @buffer.new()
  encode_integer(buf, 1337, 5, b'\x00')
  let data = buf.contents()
  let (value, offset) = decode_integer(data, 0, 5)
  inspect(value, content="1337")
  inspect(offset, content="3")
}

///|
test "RFC 7541 C.1.1 - integer 10 with 5-bit prefix" {
  let buf = @buffer.new()
  encode_integer(buf, 10, 5, b'\x00')
  let data = buf.contents()
  // Value 10 fits in 5 bits (max_prefix = 31), so it's a single byte: 0x0a
  inspect(data.length(), content="1")
  inspect(data[0].to_int(), content="10")
}

///|
test "RFC 7541 C.1.2 - integer 1337 with 5-bit prefix" {
  let buf = @buffer.new()
  encode_integer(buf, 1337, 5, b'\x00')
  let data = buf.contents()
  // 1337 with 5-bit prefix: 0x1f (31), 0x9a (154), 0x0a (10)
  // 1337 - 31 = 1306, 1306 = 128*10 + 26, so: 0x1f, (26+128)=0x9a, 0x0a
  inspect(data.length(), content="3")
  inspect(data[0].to_int(), content="31")
  inspect(data[1].to_int(), content="154")
  inspect(data[2].to_int(), content="10")
}

///|
test "integer encode/decode with prefix byte bits set" {
  let buf = @buffer.new()
  // Encode with top bit set (like indexed header 0x80)
  encode_integer(buf, 5, 7, b'\x80')
  let data = buf.contents()
  // The byte should be 0x80 | 5 = 0x85
  inspect(data[0].to_int(), content="133")
  let (value, _offset) = decode_integer(data, 0, 7)
  inspect(value, content="5")
}

// --- Huffman encoding/decoding tests ---

///|
test "huffman encode/decode round-trip for 'www.example.com'" {
  let input = string_to_bytes("www.example.com")
  let encoded = huffman_encode(input)
  let decoded = huffman_decode(encoded)
  let result = bytes_to_string(decoded)
  inspect(result, content="www.example.com")
}

///|
test "huffman encode/decode round-trip for empty string" {
  let input = string_to_bytes("")
  let encoded = huffman_encode(input)
  inspect(encoded.length(), content="0")
  let decoded = huffman_decode(encoded)
  inspect(decoded.length(), content="0")
}

///|
test "huffman encode/decode round-trip for 'no-cache'" {
  let input = string_to_bytes("no-cache")
  let encoded = huffman_encode(input)
  let decoded = huffman_decode(encoded)
  let result = bytes_to_string(decoded)
  inspect(result, content="no-cache")
}

///|
test "huffman encode/decode round-trip for 'custom-key'" {
  let input = string_to_bytes("custom-key")
  let encoded = huffman_encode(input)
  let decoded = huffman_decode(encoded)
  let result = bytes_to_string(decoded)
  inspect(result, content="custom-key")
}

///|
test "huffman table key values" {
  // 'w' (119) = (0x78, 7)
  let (code_w, bits_w) = huffman_table[119]
  inspect(code_w, content="120")
  inspect(bits_w, content="7")
  // 'o' (111) = (0x7, 5)
  let (code_o, bits_o) = huffman_table[111]
  inspect(code_o, content="7")
  inspect(bits_o, content="5")
  // '0' (48) = (0x0, 5)
  let (code_0, bits_0) = huffman_table[48]
  inspect(code_0, content="0")
  inspect(bits_0, content="5")
  // '1' (49) = (0x1, 5)
  let (code_1, bits_1) = huffman_table[49]
  inspect(code_1, content="1")
  inspect(bits_1, content="5")
  // EOS (256) = (0x3fffffff, 30)
  let (code_eos, bits_eos) = huffman_table[256]
  inspect(code_eos, content="1073741823")
  inspect(bits_eos, content="30")
}

// --- Dynamic table tests ---

///|
test "dynamic table add and get" {
  let dt = DynamicTable::new()
  dt.add("custom-header", "custom-value")
  inspect(dt.length(), content="1")
  match dt.get(0) {
    Some((name, value)) => {
      inspect(name, content="custom-header")
      inspect(value, content="custom-value")
    }
    None => inspect("should not be None", content="found entry")
  }
}

///|
test "dynamic table ordering - newest first" {
  let dt = DynamicTable::new()
  dt.add("first", "value1")
  dt.add("second", "value2")
  dt.add("third", "value3")
  inspect(dt.length(), content="3")
  // Index 0 = newest
  match dt.get(0) {
    Some((name, _)) => inspect(name, content="third")
    None => inspect("unexpected", content="found")
  }
  match dt.get(1) {
    Some((name, _)) => inspect(name, content="second")
    None => inspect("unexpected", content="found")
  }
  match dt.get(2) {
    Some((name, _)) => inspect(name, content="first")
    None => inspect("unexpected", content="found")
  }
}

///|
test "dynamic table eviction" {
  // Entry size = 32 + name.length() + value.length()
  // "a" + "b" = 32 + 1 + 1 = 34 bytes
  let dt = DynamicTable::new(max_size=70)
  dt.add("a", "b") // 34 bytes, total = 34
  dt.add("c", "d") // 34 bytes, total = 68
  inspect(dt.length(), content="2")
  dt.add("e", "f") // 34 bytes, would be 102, evict oldest until fits
  // After eviction: should have 2 entries (evicted "a"/"b")
  inspect(dt.length(), content="2")
  match dt.get(0) {
    Some((name, _)) => inspect(name, content="e")
    None => inspect("unexpected", content="found")
  }
  match dt.get(1) {
    Some((name, _)) => inspect(name, content="c")
    None => inspect("unexpected", content="found")
  }
}

///|
test "dynamic table set_max_size eviction" {
  let dt = DynamicTable::new()
  dt.add("header1", "value1")
  dt.add("header2", "value2")
  inspect(dt.length(), content="2")
  dt.set_max_size(0)
  inspect(dt.length(), content="0")
}

///|
test "dynamic table entry too large" {
  let dt = DynamicTable::new(max_size=10)
  dt.add("a", "b")
  inspect(dt.length(), content="0")
}

// --- Full HPACK encode/decode round-trip tests ---

///|
test "hpack encode/decode simple headers" {
  let encoder = Encoder::new(huffman=false)
  let decoder = Decoder::new()
  let headers : Array[(String, String)] = [
    (":method", "GET"),
    (":path", "/"),
    (":scheme", "https"),
    ("host", "example.com"),
  ]
  let encoded = encoder.encode(headers)
  let decoded = decoder.decode(encoded)
  inspect(decoded.length(), content="4")
  let (n0, v0) = decoded[0]
  inspect(n0, content=":method")
  inspect(v0, content="GET")
  let (n1, v1) = decoded[1]
  inspect(n1, content=":path")
  inspect(v1, content="/")
  let (n2, v2) = decoded[2]
  inspect(n2, content=":scheme")
  inspect(v2, content="https")
  let (n3, v3) = decoded[3]
  inspect(n3, content="host")
  inspect(v3, content="example.com")
}

///|
test "hpack encode/decode with huffman encoding" {
  let encoder = Encoder::new(huffman=true)
  let decoder = Decoder::new()
  let headers : Array[(String, String)] = [
    (":method", "GET"),
    (":path", "/index.html"),
    ("custom-key", "custom-value"),
  ]
  let encoded = encoder.encode(headers)
  let decoded = decoder.decode(encoded)
  inspect(decoded.length(), content="3")
  let (n0, v0) = decoded[0]
  inspect(n0, content=":method")
  inspect(v0, content="GET")
  let (n1, v1) = decoded[1]
  inspect(n1, content=":path")
  inspect(v1, content="/index.html")
  let (n2, v2) = decoded[2]
  inspect(n2, content="custom-key")
  inspect(v2, content="custom-value")
}

///|
test "hpack encode/decode sensitive headers" {
  let encoder = Encoder::new(huffman=false)
  let decoder = Decoder::new()
  let headers : Array[(String, String)] = [
    ("authorization", "Bearer token123"),
    ("cookie", "session=abc"),
  ]
  let encoded = encoder.encode(headers)
  let decoded = decoder.decode(encoded)
  inspect(decoded.length(), content="2")
  let (n0, v0) = decoded[0]
  inspect(n0, content="authorization")
  inspect(v0, content="Bearer token123")
  let (n1, v1) = decoded[1]
  inspect(n1, content="cookie")
  inspect(v1, content="session=abc")
  // Sensitive headers should NOT be added to the dynamic table
  inspect(encoder.dynamic_table.length(), content="0")
}

///|
test "hpack encode/decode multiple requests with dynamic table" {
  let encoder = Encoder::new(huffman=false)
  let decoder = Decoder::new()
  // First request
  let headers1 : Array[(String, String)] = [
    (":method", "GET"),
    (":path", "/"),
    ("custom-header", "value1"),
  ]
  let encoded1 = encoder.encode(headers1)
  let decoded1 = decoder.decode(encoded1)
  inspect(decoded1.length(), content="3")
  // Second request - "custom-header" should be findable in dynamic table
  let headers2 : Array[(String, String)] = [
    (":method", "GET"),
    (":path", "/other"),
    ("custom-header", "value1"),
  ]
  let encoded2 = encoder.encode(headers2)
  let decoded2 = decoder.decode(encoded2)
  inspect(decoded2.length(), content="3")
  let (n2, v2) = decoded2[2]
  inspect(n2, content="custom-header")
  inspect(v2, content="value1")
}

///|
test "static table lookups" {
  match static_table_by_name.get(":method") {
    Some(idx) => inspect(idx, content="2")
    None => inspect("not found", content="found")
  }
  match static_table_by_name.get(":path") {
    Some(idx) => inspect(idx, content="4")
    None => inspect("not found", content="found")
  }
  match static_table_by_name_value.get(":method") {
    Some(value_map) =>
      match value_map.get("GET") {
        Some(idx) => inspect(idx, content="2")
        None => inspect("not found", content="found")
      }
    None => inspect("not found", content="found")
  }
  match static_table_by_name_value.get(":status") {
    Some(value_map) =>
      match value_map.get("200") {
        Some(idx) => inspect(idx, content="8")
        None => inspect("not found", content="found")
      }
    None => inspect("not found", content="found")
  }
}

///|
test "string to bytes and back round-trip" {
  let original = "Hello, World!"
  let bytes = string_to_bytes(original)
  let result = bytes_to_string(bytes)
  inspect(result, content="Hello, World!")
}
