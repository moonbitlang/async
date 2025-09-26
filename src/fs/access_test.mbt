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
async test "exists" {
  assert_true(@fs.exists("moon.mod.json"))
  inspect(
    try? ignore(@fs.open("moon.mod.json", mode=ReadOnly)),
    content="Ok(())",
  )
  assert_false(@fs.exists("moon.mod.json.not_exist"))
  inspect(
    try? ignore(@fs.open("moon.mod.json.not_exist", mode=ReadOnly)),
    content=(
      #|Err(OSError("No such file or directory"))
    ),
  )
}

///|
async test "can_read" {
  assert_true(@fs.can_read("moon.mod.json"))
}

///|
async test "can_write" {
  assert_true(@fs.can_write("moon.mod.json"))
}

///|
async test "can_execute" {
  assert_false(@fs.can_execute("moon.mod.json"))
}
