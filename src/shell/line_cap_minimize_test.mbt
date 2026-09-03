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
async test "min line cap c cat unterminated over cap" {
  guard! @env.get_env_var("MOONBIT_ASYNC_C_CAT_PROG") is Some(program)
  let seen = []
  try
    @shell.Cmd(program, [], stdin=Text("a".repeat(1000))).each_line(
      line => seen.push(line),
      max_line_bytes=64,
    )
    |> ignore
  catch {
    err => {
      let diagnostic = "\{Repr(err)}"
      assert_true(diagnostic.contains("OutputLimitExceeded"))
      assert_true(diagnostic.contains("limit=64"))
      assert_eq(seen, [])
    }
  } noraise {
    _ => fail("expected the line limit to raise")
  }
}
