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
async fn minimized_lines_of(
  program : String,
  payload : String,
  max_line_bytes? : Int,
) -> Array[String] {
  let seen = []
  let code = @shell.Cmd(program, [], stdin=Text(payload)).each_line(
    line => seen.push(line),
    max_line_bytes?,
  )
  assert_eq(code, 0)
  seen
}

///|
async fn expect_minimized_line_limit(
  program : String,
  payload : String,
  limit : Int,
) -> Unit {
  try
    minimized_lines_of(program, payload, max_line_bytes=limit) |> ignore
  catch {
    err => {
      let diagnostic = "\{Repr(err)}"
      assert_true(diagnostic.contains("OutputLimitExceeded"))
      assert_true(diagnostic.contains("limit=\{limit}"))
    }
  } noraise {
    _ => fail("expected the line limit to raise")
  }
}

///|
fn configured_c_cat_prog() -> String? {
  @env.get_env_var("MOONBIT_ASYNC_C_CAT_PROG")
}

///|
async test "min line cap moonbit cat crlf under cap" {
  assert_eq(minimized_lines_of(cat_prog.wait(), "a\r\n", max_line_bytes=1), [
    "a",
  ])
}

///|
async test "min line cap moonbit cat exact cap" {
  assert_eq(
    minimized_lines_of(cat_prog.wait(), "aaaaaaaa\n", max_line_bytes=8),
    ["aaaaaaaa"],
  )
}

///|
async test "min line cap moonbit cat terminated over cap" {
  expect_minimized_line_limit(cat_prog.wait(), "ab\r\n", 1)
}

///|
async test "min line cap moonbit cat unterminated over cap" {
  expect_minimized_line_limit(cat_prog.wait(), "a".repeat(1000), 64)
}

///|
async test "min line cap c cat unterminated over cap" {
  match configured_c_cat_prog() {
    None => ()
    Some(program) => expect_minimized_line_limit(program, "a".repeat(1000), 64)
  }
}

///|
async test "min line cap moonbit cat original sequence" {
  assert_eq(minimized_lines_of(cat_prog.wait(), "a\r\n", max_line_bytes=1), [
    "a",
  ])
  assert_eq(
    minimized_lines_of(cat_prog.wait(), "aaaaaaaa\n", max_line_bytes=8),
    ["aaaaaaaa"],
  )
  expect_minimized_line_limit(cat_prog.wait(), "ab\r\n", 1)
  expect_minimized_line_limit(cat_prog.wait(), "a".repeat(1000), 64)
}
