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
test "with_timeout normal exit" {
  let log = StringBuilder::new()
  log.write_object(
    try? @async.with_event_loop(fn(root) {
      root.spawn_bg(fn() {
        @async.sleep(1000)
        log.write_string("one second tick\n")
      })
      @async.with_timeout(2000, fn() {
        @async.sleep(500)
        log.write_string("task finished after 500ms\n")
      })
      log.write_string("main task finished\n")
    }),
  )
  inspect(
    log.to_string(),
    content=(
      #|task finished after 500ms
      #|main task finished
      #|one second tick
      #|Ok(())
    ),
  )
}

///|
test "with_timeout failure" {
  let log = StringBuilder::new()
  log.write_object(
    try? @async.with_event_loop(fn(root) {
      root.spawn_bg(fn() {
        @async.sleep(1000)
        log.write_string("one second tick\n")
      })
      @async.with_timeout(2000, fn() {
        @async.sleep(500)
        raise Err
      }) catch {
        err => {
          log.write_string("main task fail with \{err}\n")
          raise err
        }
      }
    }),
  )
  inspect(
    log.to_string(),
    content=(
      #|main task fail with Err
      #|Err(Err)
    ),
  )
}

///|
test "with_timeout timeout" {
  let log = StringBuilder::new()
  log.write_object(
    try? @async.with_event_loop(fn(root) {
      root.spawn_bg(fn() {
        @async.sleep(1000)
        log.write_string("one second tick\n")
      })
      @async.with_timeout(500, fn() {
        @async.sleep(2000) catch {
          err => {
            log.write_string("task cancelled\n")
            raise err
          }
        }
        log.write_string("task finished after 2s\n")
      })
      log.write_string("main task finished\n")
    }),
  )
  inspect(
    log.to_string(),
    content=(
      #|task cancelled
      #|main task finished
      #|one second tick
      #|Ok(())
    ),
  )
}
