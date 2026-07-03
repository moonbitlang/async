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
#cfg(target="native")
#unsafe_skip_stub_check
#borrow(buf)
extern "C" fn websocket_random_bytes_ffi(
  buf : FixedArray[Byte],
  len : Int,
) -> Int = "moonbitlang_async_websocket_random_bytes"

///|
#cfg(target="native")
fn websocket_random_bytes(num : Int) -> Bytes raise {
  let result = FixedArray::make(num, b'\x00')
  if websocket_random_bytes_ffi(result, num) != 0 {
    raise Failure::Failure("@websocket random bytes failed")
  }
  result.unsafe_reinterpret_as_bytes()
}

///|
#cfg(target="wasm")
#unsafe_skip_stub_check
fn ms_since_epoch() -> UInt64 = "moonbitlang/async" "time/get_ms_since_epoch"

///|
#cfg(target="wasm")
let wasm_random : @random.Rand = {
  let seed = Buffer()
  let now = ms_since_epoch()
  for _ in 0..<4 {
    seed.write_uint64_le(now)
  }
  @random.Rand::chacha8(seed=seed.contents())
}

///|
#cfg(target="wasm")
fn websocket_random_bytes(num : Int) -> Bytes {
  let result = FixedArray::make(num, b'\x00')
  let mut word = 0U
  for i in 0..<num {
    if i % 4 == 0 {
      word = wasm_random.uint()
    }
    result[i] = (word >> (i % 4 * 8)).to_byte()
  }
  result.unsafe_reinterpret_as_bytes()
}

///|
fn rotate_left(x : Int, n : Int) -> Int {
  (x << n) | (x.reinterpret_as_uint() >> (32 - n)).reinterpret_as_int()
}

///|
#warnings("-unused_error_type")
fn sha1(src : Bytes) -> Bytes raise {
  let old_length = src.length()
  let bits = old_length.to_uint64() * 8
  let mut new_length = (old_length / 64 + 1) * 64
  if new_length - old_length < 9 {
    new_length += 64
  }
  let bytes = FixedArray::make(new_length, b'\x00')
  bytes.blit_from_bytes(0, src, 0, old_length)
  bytes[old_length] = 0x80
  for i in (new_length - 8)..<new_length {
    bytes[i] = (bits >> (56 - (i - (new_length - 8)) * 8)).to_byte()
  }

  let h = [0x67452301, 0xEFCDAB89, 0x98BADCFE, 0x10325476, 0xC3D2E1F0]
  let bytes_per_chunk = 64
  let chunk_count = new_length / bytes_per_chunk
  for chunk in 0..<chunk_count {
    let words = FixedArray::make(80, 0)
    for i in 0..<16 {
      let slice_start = chunk * bytes_per_chunk + i * 4
      words[i] = (bytes[slice_start].to_int() << 24) |
        (bytes[slice_start + 1].to_int() << 16) |
        (bytes[slice_start + 2].to_int() << 8) |
        bytes[slice_start + 3].to_int()
    }
    for i in 16..<80 {
      words[i] = rotate_left(
        words[i - 3] ^ words[i - 8] ^ words[i - 14] ^ words[i - 16],
        1,
      )
    }
    let v = h.copy()
    for i in 0..<80 {
      let (f, k) = if i < 20 {
        ((v[1] & v[2]) | (v[1].lnot() & v[3]), 0x5A827999)
      } else if i < 40 {
        (v[1] ^ v[2] ^ v[3], 0x6ED9EBA1)
      } else if i < 60 {
        ((v[1] & v[2]) | (v[1] & v[3]) | (v[2] & v[3]), 0x8F1BBCDC)
      } else {
        (v[1] ^ v[2] ^ v[3], 0xCA62C1D6)
      }
      let temp = rotate_left(v[0], 5) + f + v[4] + k + words[i]
      v[4] = v[3]
      v[3] = v[2]
      v[2] = rotate_left(v[1], 30)
      v[1] = v[0]
      v[0] = temp
    }
    for i in 0..<5 {
      h[i] += v[i]
    }
  }

  let result = FixedArray::make(20, b'\x00')
  for i in 0..<5 {
    result[i * 4 + 0] = (h[i].reinterpret_as_uint() >> 24).to_byte()
    result[i * 4 + 1] = (h[i].reinterpret_as_uint() >> 16).to_byte()
    result[i * 4 + 2] = (h[i].reinterpret_as_uint() >> 8).to_byte()
    result[i * 4 + 3] = h[i].to_byte()
  }
  result.unsafe_reinterpret_as_bytes()
}
