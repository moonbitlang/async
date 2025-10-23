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
test "ascii_to_string with printable ASCII" {
  let data = @encoding/utf8.encode("Hello World")
  let result = ascii_to_string(data.op_as_view())
  assert_eq(result, "Hello World")
}

///|
test "ascii_to_string with newline" {
  let data = @encoding/utf8.encode("Hello\nWorld")
  let result = ascii_to_string(data.op_as_view())
  assert_eq(result, "Hello\nWorld")
}

///|
test "ascii_to_string with tab" {
  let data = @encoding/utf8.encode("Hello\tWorld")
  let result = ascii_to_string(data.op_as_view())
  assert_eq(result, "Hello\\tWorld")
}

///|
test "ascii_to_string with carriage return" {
  let data = @encoding/utf8.encode("Hello\rWorld")
  let result = ascii_to_string(data.op_as_view())
  assert_eq(result, "Hello\\rWorld")
}
