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
#unsafe_skip_stub_check
#borrow(os_str)
fn decode_len(os_str : @c_buffer.Buffer, offset : Int, len : Int) -> Int = "moonbitlang/async" "os_string/decode_len"

///|
#unsafe_skip_stub_check
#borrow(os_str, str)
fn fill_string(
  os_str : @c_buffer.Buffer,
  offset : Int,
  len : Int,
  str : String,
  str_len : Int,
) -> Unit = "moonbitlang/async" "os_string/decode"

///|
/// Decode a host-native string buffer.
/// The host owns the platform-specific byte decoding and writes UTF-16 code
/// units into guest-owned MoonBit String storage.
pub fn decode(
  os_str : @c_buffer.Buffer,
  offset? : Int = 0,
  len? : Int = -1,
) -> String {
  let str_len = decode_len(os_str, offset, len)
  let str = String::make(str_len, '\u{0}')
  fill_string(os_str, offset, len, str, str_len)
  str
}

///|
pub let empty : OsString = encode("")
