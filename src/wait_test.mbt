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
test "wait basic" {
  let buf = StringBuilder::new()
  buf.write_object(
    try? @async.with_event_loop(fn(root) {
      root.spawn_bg(fn() {
        @async.sleep(20)
        buf.write_string("20ms tick\n")
        @async.sleep(20)
        buf.write_string("40ms tick\n")
      })
      let task = root.spawn(no_wait=true, fn() {
        @async.sleep(30)
        buf.write_string("task finished\n")
      })
      task.wait()
      buf.write_string("main task exit\n")
    }),
  )
  inspect(
    buf.to_string(),
    content=(
      #|20ms tick
      #|task finished
      #|main task exit
      #|40ms tick
      #|Ok(())
    ),
  )
}

///|
test "wait cancelled" {
  let buf = StringBuilder::new()
  buf.write_object(
    try? @async.with_event_loop(fn(root) {
      let task = root.spawn(fn() {
        @async.sleep(1000)
        buf.write_string("task finished\n")
      })
      root.spawn_bg(fn() {
        task.wait() catch {
          err => {
            buf.write_string("`wait` cancelled with \{err}\n")
            raise err
          }
        }
      })
      @async.sleep(20)
      raise Err
    }),
  )
  inspect(
    buf.to_string(),
    content=(
      #|`wait` cancelled with Cancelled
      #|Err(Err)
    ),
  )
}
