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
fn mask_payload(data : FixedArray[Byte], mask : Bytes) -> Unit {
  for i = 0; i < data.length(); i = i + 1 {
    data[i] = data[i] ^ mask[i % 4]
  }
}

///|
/// Base64 encoding
fn base64_encode(data : Bytes) -> String {
  let chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
  let data_arr = data
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
    result = result +
      chars[(combined >> 18) & 0x3F].unsafe_to_char().to_string()
    result = result +
      chars[(combined >> 12) & 0x3F].unsafe_to_char().to_string()
    if i + 1 < data_arr.length() {
      result = result +
        chars[(combined >> 6) & 0x3F].unsafe_to_char().to_string()
    } else {
      result = result + "="
    }
    if i + 2 < data_arr.length() {
      result = result + chars[combined & 0x3F].unsafe_to_char().to_string()
    } else {
      result = result + "="
    }
  }
  result
}

///|
test "base64 encode" {
  inspect(base64_encode(b"light w"), content="bGlnaHQgdw==")
  inspect(base64_encode(b"light wo"), content="bGlnaHQgd28=")
  inspect(base64_encode(b"light wor"), content="bGlnaHQgd29y")
  inspect(base64_encode(b"light work"), content="bGlnaHQgd29yaw==")
  inspect(base64_encode(b"light work."), content="bGlnaHQgd29yay4=")
  inspect(
    base64_encode(b"a Ā 𐀀 文 🦄"),
    content="YSDEgCDwkICAIOaWhyDwn6aE",
  )
}

///|
const MAGIC = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

///|
/// Generate WebSocket accept key from client key using SHA-1 and base64
fn generate_accept_key(client_key : String) -> String {
  // WebSocket magic string as defined in RFC 6455
  let combined = client_key + MAGIC
  let combined_bytes = @encoding/utf8.encode(combined)

  // Use the crypto library for proper SHA-1 hashing
  let hash = sha1(combined_bytes)

  // Use our base64 encoding function for now
  base64_encode(hash.unsafe_reinterpret_as_bytes())
}

///|
// Vendored from `moonbitlang/x/crypto:sha1.mbt`.
// TODO: once `crypto` is moved to somewhere more stable, do not vendor.
fn sha1(input : BytesView) -> FixedArray[Byte] {
  fn rotate_left(x : Int, n : Int) -> Int {
    (x << n) | (x.reinterpret_as_uint() >> (32 - n)).reinterpret_as_int()
  }

  // Padding
  let old_length = input.length()
  let bits = old_length.to_uint64() * 8
  let mut new_length = (old_length / 64 + 1) * 64
  if new_length - old_length < 9 {
    new_length += 64
  }
  let bytes = FixedArray::make(new_length, b'\x00')
  bytes.blit_from_bytesview(0, input)
  bytes[old_length] = (0x80).to_byte()
  for i = new_length - 8; i < new_length; i = i + 1 {
    bytes[i] = (bits >> (56 - (i - (new_length - 8)) * 8)).to_byte()
  }
  // Hash
  let h = [0x67452301, 0xEFCDAB89, 0x98BADCFE, 0x10325476, 0xC3D2E1F0]
  let bytes_per_chunk = 512 / 8
  let chunk_count = new_length / bytes_per_chunk // `new_length` is a multiple of 512
  for chunk = 0; chunk < chunk_count; chunk = chunk + 1 {
    let words = FixedArray::make(80, 0)
    for i = 0; i < 16; i = i + 1 {
      let slice_start = chunk * bytes_per_chunk + i * 4
      words[i] = (bytes[slice_start].to_int() << 24) |
        (bytes[slice_start + 1].to_int() << 16) |
        (bytes[slice_start + 2].to_int() << 8) |
        bytes[slice_start + 3].to_int()
    }
    for i = 16; i < 80; i = i + 1 {
      words[i] = rotate_left(
        words[i - 3] ^ words[i - 8] ^ words[i - 14] ^ words[i - 16],
        1,
      )
    }
    let v = h.copy()
    for i = 0; i < 80; i = i + 1 {
      let (f, k) = if i < 20 {
        ((v[1] & v[2]) | (v[1].lnot() & v[3]), 0x5A827999)
      } else if i < 40 {
        (v[1] ^ (v[2] ^ v[3]), 0x6ED9EBA1)
      } else if i < 60 {
        ((v[1] & v[2]) | (v[1] & v[3]) | (v[2] & v[3]), 0x8F1BBCDC)
      } else {
        (v[1] ^ (v[2] ^ v[3]), 0xCA62C1D6)
      }
      let temp = rotate_left(v[0], 5) + f + v[4] + k + words[i]
      v[4] = v[3]
      v[3] = v[2]
      v[2] = rotate_left(v[1], 30)
      v[1] = v[0]
      v[0] = temp
    }
    for i = 0; i < 5; i = i + 1 {
      h[i] += v[i]
    }
  }
  // Digest
  let result = FixedArray::make(20, b'\x00')
  for i = 0; i < 5; i = i + 1 {
    result[i * 4 + 0] = (h[i].reinterpret_as_uint() >> 24).to_byte()
    result[i * 4 + 1] = (h[i].reinterpret_as_uint() >> 16).to_byte()
    result[i * 4 + 2] = (h[i].reinterpret_as_uint() >> 8).to_byte()
    result[i * 4 + 3] = h[i].to_byte()
  }
  result
}
