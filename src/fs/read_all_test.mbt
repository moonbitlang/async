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
test "read_all basic" {
  let log = StringBuilder::new()
  @async.with_event_loop(fn(_) {
    let path = b"src/fs/moon.pkg.json"
    let r = @fs.open(path, mode=ReadOnly)
    defer r.close()
    log.write_string(r.read_all() |> @bytes_util.ascii_to_string)
  })
  inspect(
    log.to_string(),
    content=(
      #|{
      #|  "import": [
      #|    "moonbitlang/async/os_error",
      #|    "moonbitlang/async/io",
      #|    "moonbitlang/async/internal/event_loop"
      #|  ],
      #|  "test-import": [
      #|    "moonbitlang/async",
      #|    "moonbitlang/async/internal/bytes_util"
      #|  ],
      #|  "native-stub": [ "stub.c" ]
      #|}
      #|
    ),
  )
}
