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
test "collect_output" {
  @async.with_event_loop(fn(_) {
    let (code, output) = @process.collect_stdout("sh", ["-c", "printf abcd"])
    inspect(code, content="0")
    inspect(@bytes_util.ascii_to_string(output), content="abcd")
  })
}

///|
test "collect_error" {
  @async.with_event_loop(fn(_) {
    let (code, output) = @process.collect_stderr("sh", ["-c", "printf abcd >&2"])
    inspect(code, content="0")
    inspect(@bytes_util.ascii_to_string(output), content="abcd")
  })
}

///|
test "collect_output" {
  @async.with_event_loop(fn(_) {
    let (code, stdout, stderr) = @process.collect_output("sh", [
      "-c", "printf ab; printf ab >&2; printf cd; printf cd >&2",
    ])
    inspect(code, content="0")
    inspect(@bytes_util.ascii_to_string(stdout), content="abcd")
    inspect(@bytes_util.ascii_to_string(stderr), content="abcd")
  })
}
