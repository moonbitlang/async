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
#cfg(not(platform="windows"))
struct OsString(Bytes)

///|
/// Windows uses UTF-16 encoding for various things
#cfg(platform="windows")
struct OsString(String)

///|
#cfg(not(platform="windows"))
#internal(internal, "for internal FFI wrappers only")
pub fn OsString::from_bytes(data : Bytes) -> OsString {
  OsString(data)
}

///|
#cfg(platform="windows")
#internal(internal, "for internal FFI wrappers only")
pub fn OsString::from_string(data : String) -> OsString {
  OsString(data)
}

///|
#cfg(not(platform="windows"))
pub fn encode(str : StringView) -> OsString {
  @utf8.encode(str)
}

///|
#cfg(platform="windows")
pub fn encode(str : StringView) -> OsString {
  str.to_owned()
}

///|
pub impl Show for OsString with output(self, logger) {
  self.to_string().output(logger)
}

///|
#cfg(not(platform="windows"))
pub impl Show for OsString with to_string(self) {
  @utf8.decode_lossy(self.0)
}

///|
#cfg(platform="windows")
pub impl Show for OsString with to_string(self) {
  self.0
}

///|
/// `len`, if present, is the number of bytes to decode in `os_str`.
/// The default value is determined using `strlen` or `wcslen`.
#cfg(not(platform="windows"))
pub fn decode(
  os_str : @c_buffer.Buffer,
  len? : Int = os_str.strlen(),
) -> String {
  let data = FixedArray::make(len, b'\x00')
  os_str.blit_to_bytes(dst=data, offset=0, len~)
  @utf8.decode_lossy(data.unsafe_reinterpret_as_bytes())
}

///|
#cfg(platform="windows")
#borrow(out)
extern "C" fn decode_fill(
  os_str : @c_buffer.Buffer,
  len : Int,
  out : String,
  out_len : Int,
) -> Int = "moonbitlang_async_c_buffer_fill_string"

///|
#cfg(platform="windows")
pub fn decode(os_str : @c_buffer.Buffer, len? : Int = -1) -> String {
  let buffer_len = if len >= 0 { len / 2 } else { 1024 }
  let buffer = String::make(buffer_len, '\u{0}')
  let actual_len = decode_fill(os_str, len, buffer, buffer_len)
  if actual_len <= buffer_len {
    if actual_len == buffer_len {
      buffer
    } else {
      buffer[:actual_len].to_owned()
    }
  } else {
    let result = String::make(actual_len, '\u{0}')
    if decode_fill(os_str, len, result, actual_len) == actual_len {
      result
    } else {
      ""
    }
  }
}

///|
#cfg(platform="windows")
let _mute_unused_warning : Unit = ignore(@utf8.encode(""))
