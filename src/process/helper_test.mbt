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
async test "collect_stdout" {
  let (code, output) = @process.collect_stdout("sh", ["-c", "printf abcd"])
  inspect(code, content="0")
  inspect(output.text(), content="abcd")
}

///|
async test "collect_error" {
  let (code, output) = @process.collect_stderr("sh", ["-c", "printf abcd >&2"])
  inspect(code, content="0")
  inspect(output.text(), content="abcd")
}

///|
async test "collect_output" {
  let (code, stdout, stderr) = @process.collect_output("sh", [
    "-c", "printf ab; printf ab >&2; printf cd; printf cd >&2",
  ])
  inspect(code, content="0")
  inspect(stdout.text(), content="abcd")
  inspect(stderr.text(), content="abcd")
}

///|
async test "collect_output_merged" {
  let (code, output) = @process.collect_output_merged("sh", [
    "-c", "printf ab; printf ab >&2; printf cd; printf cd >&2",
  ])
  inspect(code, content="0")
  inspect(output.text(), content="ababcdcd")
}
