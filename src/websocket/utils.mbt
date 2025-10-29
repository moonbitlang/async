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
/// Apply XOR mask to payload data
fn mask_payload(data : FixedArray[Byte], mask : FixedArray[Byte]) -> Unit {
  for i = 0; i < data.length(); i = i + 1 {
    data[i] = data[i] ^ mask[i % 4]
  }
}

///|
/// Generate a random 4-byte masking key
fn generate_mask() -> FixedArray[Byte] {
  let mask = FixedArray::make(4, b'\x00')
  // Use simple random generation - in production, use cryptographically secure random
  // Using current time as seed for simple randomness
  let t = 123456 // Placeholder - should use actual time/random source
  mask[0] = (t % 256).to_byte()
  mask[1] = (t / 256 % 256).to_byte()
  mask[2] = (t / 65536 % 256).to_byte()
  mask[3] = (t / 16777216 % 256).to_byte()
  mask
}

///|
/// Encode a 16-bit integer in big-endian format
fn encode_u16(value : Int) -> Bytes {
  let bytes = FixedArray::make(2, b'\x00')
  bytes[0] = ((value >> 8) & 0xFF).to_byte()
  bytes[1] = (value & 0xFF).to_byte()
  bytes.unsafe_reinterpret_as_bytes()
}

///|
/// Decode a 16-bit big-endian integer
fn decode_u16(bytes : BytesView) -> Int {
  (bytes[0].to_int() << 8) | bytes[1].to_int()
}

///|
/// Encode a 64-bit integer in big-endian format
fn encode_u64(value : Int64) -> Bytes {
  let bytes = FixedArray::make(8, b'\x00')
  bytes[0] = ((value >> 56) & 0xFFL).to_int().to_byte()
  bytes[1] = ((value >> 48) & 0xFFL).to_int().to_byte()
  bytes[2] = ((value >> 40) & 0xFFL).to_int().to_byte()
  bytes[3] = ((value >> 32) & 0xFFL).to_int().to_byte()
  bytes[4] = ((value >> 24) & 0xFFL).to_int().to_byte()
  bytes[5] = ((value >> 16) & 0xFFL).to_int().to_byte()
  bytes[6] = ((value >> 8) & 0xFFL).to_int().to_byte()
  bytes[7] = (value & 0xFFL).to_int().to_byte()
  bytes.unsafe_reinterpret_as_bytes()
}

///|
/// Decode a 64-bit big-endian integer
fn decode_u64(bytes : BytesView) -> Int64 {
  let b0 = bytes[0].to_int().to_int64() << 56
  let b1 = bytes[1].to_int().to_int64() << 48
  let b2 = bytes[2].to_int().to_int64() << 40
  let b3 = bytes[3].to_int().to_int64() << 32
  let b4 = bytes[4].to_int().to_int64() << 24
  let b5 = bytes[5].to_int().to_int64() << 16
  let b6 = bytes[6].to_int().to_int64() << 8
  let b7 = bytes[7].to_int().to_int64()
  b0 | b1 | b2 | b3 | b4 | b5 | b6 | b7
}

///|
/// Simple SHA-1 implementation for WebSocket handshake
fn sha1(data : Bytes) -> Bytes {
  // Initialize hash values
  let mut h0 = 0x67452301
  let mut h1 = 0xEFCDAB89
  let mut h2 = 0x98BADCFE
  let mut h3 = 0x10325476
  let mut h4 = 0xC3D2E1F0

  // Pre-processing: adding padding bits
  let data_arr = data.to_fixedarray()
  let original_bit_len = data_arr.length() * 8

  // Calculate padding needed
  let mut msg_len = data_arr.length()
  msg_len += 1 // for the 1 bit
  while msg_len % 64 != 56 {
    msg_len += 1
  }
  msg_len += 8 // for the 64-bit length
  let padded = FixedArray::make(msg_len, b'\x00')

  // Copy original data
  for i = 0; i < data_arr.length(); i = i + 1 {
    padded[i] = data_arr[i]
  }

  // Add padding bit
  padded[data_arr.length()] = b'\x80'

  // Add length as 64-bit big-endian
  let bit_len = original_bit_len.to_int64()
  for i = 0; i < 8; i = i + 1 {
    padded[msg_len - 8 + i] = ((bit_len >> (56 - i * 8)) & 0xFFL)
      .to_int()
      .to_byte()
  }

  // Process message in 512-bit chunks
  for chunk_start = 0; chunk_start < msg_len; chunk_start = chunk_start + 64 {
    let w = FixedArray::make(80, 0)

    // Break chunk into sixteen 32-bit big-endian words
    for i = 0; i < 16; i = i + 1 {
      let base = chunk_start + i * 4
      w[i] = (padded[base].to_int() << 24) |
        (padded[base + 1].to_int() << 16) |
        (padded[base + 2].to_int() << 8) |
        padded[base + 3].to_int()
    }

    // Extend the sixteen 32-bit words into eighty 32-bit words
    for i = 16; i < 80; i = i + 1 {
      w[i] = left_rotate(w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16], 1)
    }

    // Initialize hash value for this chunk
    let mut a = h0
    let mut b = h1
    let mut c = h2
    let mut d = h3
    let mut e = h4

    // Main loop
    for i = 0; i < 80; i = i + 1 {
      let f = if i < 20 {
        (b & c) | (b.lnot() & d)
      } else if i < 40 {
        b ^ c ^ d
      } else if i < 60 {
        (b & c) | (b & d) | (c & d)
      } else {
        b ^ c ^ d
      }
      let k = if i < 20 {
        0x5A827999
      } else if i < 40 {
        0x6ED9EBA1
      } else if i < 60 {
        0x8F1BBCDC
      } else {
        0xCA62C1D6
      }
      let temp = (left_rotate(a, 5) + f + e + k + w[i]) & 0xFFFFFFFF
      e = d
      d = c
      c = left_rotate(b, 30)
      b = a
      a = temp
    }

    // Add this chunk's hash to result
    h0 = (h0 + a) & 0xFFFFFFFF
    h1 = (h1 + b) & 0xFFFFFFFF
    h2 = (h2 + c) & 0xFFFFFFFF
    h3 = (h3 + d) & 0xFFFFFFFF
    h4 = (h4 + e) & 0xFFFFFFFF
  }

  // Produce the final hash value as a 160-bit number
  let result = FixedArray::make(20, b'\x00')
  for i = 0; i < 4; i = i + 1 {
    result[i] = ((h0 >> (24 - i * 8)) & 0xFF).to_byte()
    result[4 + i] = ((h1 >> (24 - i * 8)) & 0xFF).to_byte()
    result[8 + i] = ((h2 >> (24 - i * 8)) & 0xFF).to_byte()
    result[12 + i] = ((h3 >> (24 - i * 8)) & 0xFF).to_byte()
    result[16 + i] = ((h4 >> (24 - i * 8)) & 0xFF).to_byte()
  }
  result.unsafe_reinterpret_as_bytes()
}

///|
/// Left rotate a 32-bit integer
fn left_rotate(value : Int, amount : Int) -> Int {
  ((value << amount) | (value >> (32 - amount))) & 0xFFFFFFFF
}

///|
/// Base64 encoding
fn base64_encode(data : Bytes) -> String {
  let chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
  let data_arr = data.to_fixedarray()
  let mut result = ""
  for i = 0; i < data_arr.length(); i = i + 3 {
    let b1 = data_arr[i].to_int()
    let b2 = if i + 1 < data_arr.length() {
      data_arr[i + 1].to_int()
    } else {
      0
    }
    let b3 = if i + 2 < data_arr.length() {
      data_arr[i + 2].to_int()
    } else {
      0
    }
    let combined = (b1 << 16) | (b2 << 8) | b3
    result = result + chars[(combined >> 18) & 0x3F].to_string()
    result = result + chars[(combined >> 12) & 0x3F].to_string()
    if i + 1 < data_arr.length() {
      result = result + chars[(combined >> 6) & 0x3F].to_string()
    } else {
      result = result + "="
    }
    if i + 2 < data_arr.length() {
      result = result + chars[combined & 0x3F].to_string()
    } else {
      result = result + "="
    }
  }
  result
}

///|
/// Generate WebSocket accept key from client key using SHA-1 and base64
fn generate_accept_key(client_key : String) -> String {
  // WebSocket magic string
  let magic = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
  let combined = client_key + magic
  let combined_bytes = @encoding/utf8.encode(combined)
  let hash = sha1(combined_bytes)
  base64_encode(hash)
}
