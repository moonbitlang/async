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
struct OsString(String)

///|
pub fn encode(str : StringView) -> OsString {
  OsString(str.to_owned())
}

///|
pub impl Show for OsString with fn output(self, logger) {
  self.to_string().output(logger)
}

///|
pub impl Show for OsString with fn to_string(self) {
  self.0
}

///|
/// Wasm `OsString` is always UTF-16LE, matching MoonBit String storage.
/// `len`, if present, is the number of UTF-16 bytes to decode in `os_str`.
pub fn decode(os_str : @c_buffer.Buffer, len? : Int = -1) -> String {
  let len = if len == -1 {
    wchar_len(os_str)
  } else {
    len
  }
  let data = FixedArray::make(len, b'\x00')
  os_str.blit_to_bytes(dst=data, offset=0, len~)
  @utf16.decode_lossy(data.unsafe_reinterpret_as_bytes())
}

///|
fn wchar_len(os_str : @c_buffer.Buffer) -> Int {
  let mut len = 0
  while os_str[len] != b'\x00' || os_str[len + 1] != b'\x00' {
    len += 2
  }
  len
}
