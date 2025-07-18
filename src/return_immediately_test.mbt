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
test "return_immediately basic" {
  let log = StringBuilder::new()
  log.write_object(
    try? @async.with_event_loop(fn(root) {
      root.spawn_bg(fn() {
        @async.sleep(100)
        root.return_immediately(())
      })
      root.spawn_bg(fn() {
        @async.sleep(150)
        log.write_string("task finished\n")
      })
    }),
  )
  inspect(log.to_string(), content="Ok(())")
}

///|
test "return_immediately nested" {
  let log = StringBuilder::new()
  log.write_object(
    try? @async.with_event_loop(fn(root) {
      root.spawn_bg(fn() {
        @async.sleep(150)
        log.write_string("outer task finished\n")
      })
      @async.with_task_group(fn(group) {
        group.spawn_bg(fn() {
          @async.sleep(100)
          root.return_immediately(())
        })
        group.spawn_bg(fn() {
          @async.sleep(150)
          log.write_string("inner task finished\n")
        })
      })
    }),
  )
  inspect(log.to_string(), content="Ok(())")
}

///|
test "return_immediately error on cancel" {
  let log = StringBuilder::new()
  log.write_object(
    try? @async.with_event_loop(fn(root) {
      root.spawn_bg(fn() {
        @async.sleep(100)
        root.return_immediately(())
      })
      root.spawn_bg(fn() {
        @async.sleep(150) catch {
          _ => {
            log.write_string("task cancelled, causing other error\n")
            raise Err
          }
        }
        log.write_string("task finished\n")
      })
    }),
  )
  inspect(
    log.to_string(),
    content=(
      #|task cancelled, causing other error
      #|Err(Err)
    ),
  )
}
