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
pub fn ascii_to_string(bytes : Bytes) -> String {
  let builder = StringBuilder::new()
  for b in bytes {
    match b {
      '\r' => builder.write_string("\\r")
      '\n' => builder.write_string("\\n")
      b => builder.write_char(b.to_int().unsafe_to_char())
    }
  }
  builder.to_string()
}

///|
fn String::to_ascii(str : String) -> Bytes {
  Bytes::makei(str.length(), i => str.unsafe_charcode_at(i).to_byte())
}

///|
fn @bytes.View::find_index(self : @bytes.View, byte : Byte) -> Int? {
  for i in 0..<self.length() {
    if self[i] == byte {
      break Some(i)
    }
  } else {
    None
  }
}

///|
fn @bytes.View::rev_find_index(self : @bytes.View, byte : Byte) -> Int? {
  for i = self.length() - 1; i >= 0; i = i - 1 {
    if self[i] == byte {
      break Some(i)
    }
  } else {
    None
  }
}
