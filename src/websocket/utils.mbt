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
  let hash = @crypto.sha1(combined_bytes)
  base64_encode(hash.unsafe_reinterpret_as_bytes())
}
