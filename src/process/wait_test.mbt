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
async test "basic wait" {
  let log = StringBuilder::new()
  @async.with_task_group(fn(root) {
    root.spawn_bg(fn() {
      for i in 0..<4 {
        @async.sleep(300)
        log.write_string("\{(i + 1) * 300}ms tick\n")
      }
    })
    let result = @process.run(b"sh", [b"-c", b"sleep 1"])
    log.write_string("process completed with \{result}\n")
  })
  inspect(
    log.to_string(),
    content=(
      #|300ms tick
      #|600ms tick
      #|900ms tick
      #|process completed with 0
      #|1200ms tick
      #|
    ),
  )
}

///|
async test "wait exitcode" {
  inspect(@process.run(b"sh", [b"-c", b"exit 42"]), content="42")
}
