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
async test "basic_timer" {
  let buf = StringBuilder::new()
  let result = try? @async.with_task_group(fn(root) {
    root.spawn_bg(fn() {
      @async.sleep(100)
      buf.write_string("task 1, tick 1\n")
      @async.sleep(200)
      buf.write_string("task 1, tick 2\n")
      @async.sleep(200)
      buf.write_string("task 1, tick 3\n")
    })
    root.spawn_bg(fn() {
      @async.sleep(200)
      buf.write_string("task 2, tick 1\n")
      @async.sleep(200)
      buf.write_string("task 2, tick 2\n")
      @async.sleep(200)
      buf.write_string("task 2, tick 3\n")
    })
  })
  inspect(result, content="Ok(())")
  inspect(
    buf.to_string(),
    content=(
      #|task 1, tick 1
      #|task 2, tick 1
      #|task 1, tick 2
      #|task 2, tick 2
      #|task 1, tick 3
      #|task 2, tick 3
      #|
    ),
  )
}
