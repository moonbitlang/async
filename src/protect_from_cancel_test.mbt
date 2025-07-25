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
test "protect_from_cancel" {
  let log = StringBuilder::new()
  log.write_object(
    try? @async.with_event_loop(fn(root) {
      root.spawn_bg(fn() {
        @async.protect_from_cancel(fn() {
          @async.sleep(200) catch {
            err => {
              log.write_string("critial job cancelled with error \{err}\n")
              raise err
            }
          }
          log.write_string("critical job finished\n")
        }) catch {
          err => {
            log.write_string("job cancelled after critical part\n")
            raise err
          }
        }
        @async.sleep(200)
        log.write_string("non-critial part of job finished\n")
      })
      root.spawn_bg(fn() {
        @async.sleep(200) catch {
          err => {
            log.write_string("non-critial job cancelled with error \{err}\n")
            raise err
          }
        }
        log.write_string("non-critical job finished\n")
      })
      @async.sleep(100)
      raise Err
    }),
  )
  inspect(
    log.to_string(),
    content=(
      #|non-critial job cancelled with error Cancelled
      #|critical job finished
      #|job cancelled after critical part
      #|Err(Err)
    ),
  )
}

///|
test "protect_from_cancel wait" {
  let log = StringBuilder::new()
  log.write_object(
    try? @async.with_event_loop(fn(root) {
      root.spawn_bg(fn() {
        @async.sleep(100)
        log.write_string("100ms tick\n")
        @async.sleep(100)
        log.write_string("200ms tick\n")
      })
      @async.with_task_group(fn(group) {
        group.spawn_bg(fn() {
          @async.sleep(150)
          log.write_string(
            "trying to cancel the group containing critial job\n",
          )
          raise Err
        })
        @async.protect_from_cancel(fn() {
          @async.sleep(250)
          log.write_string("critial job finished\n")
        })
      }) catch {
        _ => ()
      }
      log.write_string("task group containing critical job finished\n")
    }),
  )
  inspect(
    log.to_string(),
    content=(
      #|100ms tick
      #|trying to cancel the group containing critial job
      #|200ms tick
      #|critial job finished
      #|task group containing critical job finished
      #|Ok(())
    ),
  )
}

///|
test "protect_from_cancel with_timeout" {
  let log = StringBuilder::new()
  log.write_object(
    try? @async.with_event_loop(fn(root) {
      root.spawn_bg(fn() {
        @async.sleep(100)
        log.write_string("100ms tick\n")
        @async.sleep(100)
        log.write_string("200ms tick\n")
      })
      @async.with_timeout(150, fn() {
        @async.protect_from_cancel(fn() {
          @async.sleep(250)
          log.write_string("critial job finished\n")
        })
      })
      log.write_string("`with_timeout` containing critical job finished\n")
    }),
  )
  inspect(
    log.to_string(),
    content=(
      #|100ms tick
      #|200ms tick
      #|critial job finished
      #|`with_timeout` containing critical job finished
      #|Ok(())
    ),
  )
}

///|
test "protect_from_cancel fail" {
  let log = StringBuilder::new()
  log.write_object(
    try? @async.with_event_loop(fn(root) {
      root.spawn_bg(fn() {
        @async.sleep(100)
        log.write_string("100ms tick\n")
        @async.sleep(100)
        log.write_string("200ms tick\n")
      })
      @async.with_timeout(150, fn() {
        @async.protect_from_cancel(fn() {
          @async.sleep(250)
          log.write_string("critial job fail\n")
          raise Err
        })
      })
    }),
  )
  inspect(
    log.to_string(),
    content=(
      #|100ms tick
      #|200ms tick
      #|critial job fail
      #|Err(Err)
    ),
  )
}

///|
test "protect_from_cancel nested1" {
  let log = StringBuilder::new()
  log.write_object(
    try? @async.with_event_loop(fn(root) {
      root.spawn_bg(fn() {
        @async.sleep(100)
        log.write_string("100ms tick\n")
        @async.sleep(100)
        log.write_string("200ms tick\n")
      })
      @async.with_timeout(150, fn() {
        @async.protect_from_cancel(fn() {
          @async.protect_from_cancel(fn() {
            @async.sleep(250)
            log.write_string("critial job finished\n")
          })
        })
      })
      log.write_string("`with_timeout` containing critical job finished\n")
    }),
  )
  inspect(
    log.to_string(),
    content=(
      #|100ms tick
      #|200ms tick
      #|critial job finished
      #|`with_timeout` containing critical job finished
      #|Ok(())
    ),
  )
}

///|
test "protect_from_cancel nested2" {
  let log = StringBuilder::new()
  log.write_object(
    try? @async.with_event_loop(fn(root) {
      root.spawn_bg(fn() {
        @async.sleep(100)
        log.write_string("100ms tick\n")
        @async.sleep(100)
        log.write_string("200ms tick\n")
      })
      @async.with_timeout(150, fn() {
        @async.protect_from_cancel(fn() {
          @async.protect_from_cancel(fn() {
            @async.sleep(50)
            log.write_string("inner critial job finished\n")
          })
          @async.sleep(200)
          log.write_string("outer critial job finished\n")
        })
      })
      log.write_string("`with_timeout` containing critical job finished\n")
    }),
  )
  inspect(
    log.to_string(),
    content=(
      #|inner critial job finished
      #|100ms tick
      #|200ms tick
      #|outer critial job finished
      #|`with_timeout` containing critical job finished
      #|Ok(())
    ),
  )
}

///|
test "protect_from_cancel in cancellation handler" {
  let log = StringBuilder::new()
  log.write_object(
    try? @async.with_event_loop(fn(root) {
      root.spawn_bg(no_wait=true, fn() {
        @async.sleep(100) catch {
          err => {
            log.write_string("cancelled with error \{err}\n")
            @async.protect_from_cancel(fn() {
              @async.sleep(50)
              log.write_string("critial cancellation handler terminated\n")
            })
            raise err
          }
        }
      })
      @async.sleep(50)
      log.write_string("start cancellation\n")
    }),
  )
  inspect(
    log.to_string(),
    content=(
      #|start cancellation
      #|cancelled with error Cancelled
      #|critial cancellation handler terminated
      #|Ok(())
    ),
  )
}

///|
test "cancel while scheduled" {
  let log = StringBuilder::new()
  @async.with_event_loop(fn(root) {
    root.spawn_bg(fn() {
      for _ in 0..<2 {
        @async.sleep(20)
        log.write_string("tick\n")
      }
    })
    let task1 = root.spawn(allow_failure=true, fn() {
      // after calling `pause`, current coroutine would be in `run_later`,
      // and it will receive cancellation in this situation
      @async.pause() catch {
        err => {
          log.write_string("`pause` cancelled with \{err}\n")
          @async.protect_from_cancel(fn() {
            // Now, due to `protect_from_cancel`,
            // we are allowed to suspend inside cancellation handler.
            // However, since current coroutine is still in `run_later`,
            // the scheduler will wakeup current coroutine immediately,
            // before the timer expires.
            @async.sleep(30)
            log.write_string("async cleanup finished\n")
          })
          raise err
        }
      }
    })
    root.spawn_bg(fn() { task1.cancel() })
  })
  inspect(
    log.to_string(),
    content=(
      #|`pause` cancelled with Cancelled
      #|tick
      #|async cleanup finished
      #|tick
      #|
    ),
  )
}

///|
test "error in async cancel" {
  let log = StringBuilder::new()
  @async.with_event_loop(fn(root) {
    root.spawn_bg(fn() {
      for _ in 0..<3 {
        @async.sleep(20)
        log.write_string("tick\n")
      }
    })
    log.write_object(
      try? @async.with_task_group(fn(group) {
        group.spawn_bg(no_wait=true, allow_failure=true, fn() {
          @async.sleep(1000) catch {
            _ => {
              log.write_string("performing async cleanup\n")
              @async.protect_from_cancel(fn() {
                @async.sleep(20)
                log.write_string("raising error from async cleanup\n")
                raise Err
              })
            }
          }
        })
        @async.sleep(10)
        log.write_string("main task of inner group done\n")
      }),
    )
    log.write_string("\ngroup terminates\n")
  })
  inspect(
    log.to_string(),
    content=(
      #|main task of inner group done
      #|performing async cleanup
      #|tick
      #|raising error from async cleanup
      #|Ok(())
      #|group terminates
      #|tick
      #|tick
      #|
    ),
  )
}
