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
test "missing_close" {
  let log = StringBuilder::new()
  @async.with_event_loop(fn(root) {
    let (r, w) = @pipe.pipe()
    root.spawn_bg(fn() {
      let data = r.read_exactly(4)
      log.write_string("received \{data}\n")
    })
    root.spawn_bg(fn() {
      let data = b"abcd"
      w.write(data)
      log.write_string("written \{data}\n")
    })
  })
  inspect(
    log.to_string(),
    content=(
      #|written b"\x61\x62\x63\x64"
      #|received b"\x61\x62\x63\x64"
      #|
    ),
  )
}
