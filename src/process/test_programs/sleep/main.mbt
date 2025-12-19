///|
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
extern "C" fn register_termination_handler() = "register_termination_handler"

///|
extern "C" fn exit(code : Int) = "exit"

///|
async fn main {
  register_termination_handler()
  let mut time = 10_000
  let mut exit_code = 0
  loop @env.args()[1:] {
    [] => ()
    ["-exit-code", .. rest] => {
      guard rest is [code, .. rest] else { fail("invalid arguments") }
      exit_code = @strconv.parse_int(code)
      continue rest
    }
    [['-', ..] as flag, ..] => fail("unrecognized argument \{flag}")
    [t, .. rest] => {
      time = @strconv.parse_int(t)
      continue rest
    }
  }
  @async.sleep(time)
  exit(exit_code)
}
