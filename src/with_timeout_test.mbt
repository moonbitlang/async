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
        @async.sleep(30)
        log.write_string("30ms tick\n")
      })
      @async.with_timeout(40, fn() {
        @async.sleep(20)
        log.write_string("task finished after 100ms\n")
      })
      log.write_string("main task finished\n")
    }),
  )
  inspect(
    log.to_string(),
    content=(
      #|task finished after 100ms
      #|main task finished
      #|30ms tick
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
        @async.sleep(30)
        log.write_string("30ms tick\n")
      })
      @async.with_timeout(40, fn() {
        @async.sleep(20)
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
        @async.sleep(30)
        log.write_string("30ms tick\n")
      })
      @async.with_timeout(20, fn() {
        @async.sleep(40) catch {
          err => {
            log.write_string("task cancelled\n")
            raise err
          }
        }
        log.write_string("task finished\n")
      })
      log.write_string("main task finished\n")
    }),
  )
  inspect(
    log.to_string(),
    content=(
      #|task cancelled
      #|main task finished
      #|30ms tick
      #|Ok(())
    ),
  )
}

///|
test "with_timeout nested1" {
  let log = StringBuilder::new()
  log.write_object(
    try? @async.with_event_loop(fn(root) {
      root.spawn_bg(fn() {
        @async.sleep(20)
        log.write_string("20ms tick\n")
        @async.sleep(20)
        log.write_string("40ms tick\n")
      })
      @async.with_timeout(30, fn() {
        @async.with_timeout(50, fn() {
          @async.sleep(2000) catch {
            err => {
              log.write_string("task cancelled\n")
              raise err
            }
          }
          log.write_string("task finished after 2s\n")
        })
      })
      log.write_string("main task finished\n")
    }),
  )
  inspect(
    log.to_string(),
    content=(
      #|20ms tick
      #|task cancelled
      #|main task finished
      #|40ms tick
      #|Ok(())
    ),
  )
}

///|
test "with_timeout nested2" {
  let log = StringBuilder::new()
  log.write_object(
    try? @async.with_event_loop(fn(root) {
      root.spawn_bg(fn() {
        @async.sleep(20)
        log.write_string("20ms tick\n")
        @async.sleep(20)
        log.write_string("40ms tick\n")
      })
      @async.with_timeout(50, fn() {
        @async.with_timeout(30, fn() {
          @async.sleep(2000) catch {
            err => {
              log.write_string("task cancelled\n")
              raise err
            }
          }
          log.write_string("task finished after 2s\n")
        })
      })
      log.write_string("main task finished\n")
    }),
  )
  inspect(
    log.to_string(),
    content=(
      #|20ms tick
      #|task cancelled
      #|main task finished
      #|40ms tick
      #|Ok(())
    ),
  )
}

///|
test "with_timeout error_on_cancel" {
  let log = StringBuilder::new()
  log.write_object(
    try? @async.with_event_loop(fn(root) {
      root.spawn_bg(fn() {
        @async.sleep(30)
        log.write_string("30ms tick\n")
      })
      @async.with_timeout(20, fn() {
        @async.sleep(2000) catch {
          _ => {
            log.write_string("causing other error on cancellation\n")
            raise Err
          }
        }
        log.write_string("task finished after 100ms\n")
      })
      log.write_string("main task finished\n")
    }),
  )
  inspect(
    log.to_string(),
    content=(
      #|causing other error on cancellation
      #|Err(Err)
    ),
  )
}

///|
test "with_timeout error-on-timeout" {
  let log = StringBuilder::new()
  log.write_object(
    try? @async.with_event_loop(fn(root) {
      root.spawn_bg(fn() {
        @async.sleep(50)
        log.write_string("50ms tick\n")
      })
      defer log.write_string("main task terminates\n")
      @async.with_timeout(25, error=Err, fn() {
        @async.sleep(2000) catch {
          err => {
            log.write_string("task cancelled\n")
            raise err
          }
        }
        log.write_string("task finished after 2s\n")
      })
    }),
  )
  inspect(
    log.to_string(),
    content=(
      #|task cancelled
      #|main task terminates
      #|Err(Err)
    ),
  )
}

///|
test "with_timeout_opt normal exit" {
  let log = StringBuilder::new()
  log.write_object(
    try? @async.with_event_loop(fn(root) {
      root.spawn_bg(fn() {
        @async.sleep(50)
        log.write_string("50ms tick\n")
      })
      log.write_object(
        @async.with_timeout_opt(1000, fn() {
          @async.sleep(25)
          log.write_string("task finished after 25ms\n")
          42
        }),
      )
      log.write_char('\n')
    }),
  )
  inspect(
    log.to_string(),
    content=(
      #|task finished after 25ms
      #|Some(42)
      #|50ms tick
      #|Ok(())
    ),
  )
}

///|
test "with_timeout_opt failure" {
  let log = StringBuilder::new()
  log.write_object(
    try? @async.with_event_loop(fn(root) {
      root.spawn_bg(fn() {
        @async.sleep(50)
        log.write_string("50ms tick\n")
      })
      @async.with_timeout(1000, fn() {
        @async.sleep(20)
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
test "with_timeout_opt timeout" {
  let log = StringBuilder::new()
  log.write_object(
    try? @async.with_event_loop(fn(root) {
      root.spawn_bg(fn() {
        @async.sleep(50)
        log.write_string("50ms tick\n")
      })
      log.write_object(
        @async.with_timeout_opt(25, fn() {
          try @async.sleep(2000) catch {
            err => {
              log.write_string("task cancelled\n")
              raise err
            }
          } noraise {
            _ => {
              log.write_string("task finished after 2s\n")
              42
            }
          }
        }),
      )
      log.write_char('\n')
    }),
  )
  inspect(
    log.to_string(),
    content=(
      #|task cancelled
      #|None
      #|50ms tick
      #|Ok(())
    ),
  )
}
