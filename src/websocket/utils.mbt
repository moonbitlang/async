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
fn mask_payload(
  data : FixedArray[Byte],
  mask : Bytes,
  offset~ : Int,
  len~ : Int,
  mask_offset? : Int = 0,
) -> Unit {
  for i = 0; i < len; i = i + 1 {
    data[offset + i] = data[offset + i] ^ mask[(mask_offset + i) % 4]
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
  let hash = @tls.sha1(combined_bytes)

  // Use our base64 encoding function for now
  base64_encode(hash)
}

///|
fn verify_utf8(data : BytesView, remaining~ : Int) -> Int raise {
  for i = 0, remaining = remaining; i < data.length(); {
    match (remaining, data.unsafe_get(i)) {
      (0, 0..<0x80) => continue i + 1, 0
      (0, 0xc0..<0xe0) => continue i + 1, 1
      (0, 0xe0..<0xf0) => continue i + 1, 2
      (0, 0xf0) => continue i + 1, 3
      (0, _) => {
        ignore(@encoding/utf8.decode(data[i:i + 1]))
        panic()
      }
      (remaining, 0x80..<0xc0) => continue i + 1, remaining - 1
      (_, byte) => {
        ignore(@encoding/utf8.decode([0xc0, byte]))
        panic()
      }
    }
  } else {
    remaining
  }
}
