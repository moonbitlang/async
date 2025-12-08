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
struct OsString(Bytes)

///|
pub fn encode(str : StringView) -> OsString {
  @encoding/utf8.encode(str)
}

///|
pub impl Show for OsString with output(self, logger) {
  self.to_string().output(logger)
}

///|
pub impl Show for OsString with to_string(self) {
  @encoding/utf8.decode_lossy(self.0)
}

///|
pub fn decode(os_str : @c_buffer.Buffer) -> String {
  let len = os_str.strlen()
  let data = FixedArray::make(len, b'\x00')
  os_str.blit_to_bytes(dst=data, offset=0, len~)
  @encoding/utf8.decode_lossy(data.unsafe_reinterpret_as_bytes())
}
