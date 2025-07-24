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
fn ascii_to_string(ascii : Bytes) -> String {
  let builder = StringBuilder::new()
  for byte in ascii {
    builder.write_char(byte.to_int().unsafe_to_char())
  }
  builder.to_string()
}

///|
test "read_all" {
  let log = StringBuilder::new()
  @async.with_event_loop(fn(_) {
    let dir = @fs.opendir("src\x00")
    defer dir.close()
    let list = dir.read_all().map(ascii_to_string)
    list.sort()
    log.write_object(list)
  })
  inspect(
    log.to_string(),
    content=(
      #|["fs", "pipe", "aqueue", "socket", "example", "internal", "os_error", "task.mbt", "async.mbt", "async.mbti", "moon.pkg.json", "wait_test.mbt", "pause_test.mbt", "spawn_test.mbt", "task_group.mbt", "timer_test.mbt", "worker_test.mbt", "no_wait_test.mbt", "spawn_loop_test.mbt", "group_defer_test.mbt", "cancellation_test.mbt", "with_timeout_test.mbt", "allow_failure_test.mbt", "missing_close_test.mbt", "return_immediately_test.mbt", "protect_from_cancel_test.mbt"]
    ),
  )
}
