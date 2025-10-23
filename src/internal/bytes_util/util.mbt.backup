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
pub fn ascii_to_string(ascii : BytesView) -> String {
  let builder = StringBuilder::new()
  for byte in ascii {
    match byte {
      '\n' => builder.write_char('\n')
      '\r' => builder.write_string("\\r")
      '\t' => builder.write_string("\\t")
      32..=126 => builder.write_char(byte.to_int().unsafe_to_char())
      x =>
        builder
        ..write_string("\\x")
        ..write_string(x.to_int().to_string(radix=16))
    }
  }
  builder.to_string()
}
