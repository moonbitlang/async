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
test "group defer basic" {
  let log = StringBuilder::new()
  @async.with_event_loop(fn(root) {
    root.add_defer(() => log.write_string("first group defer\n"))
    root.spawn_bg(fn() {
      defer log.write_string("defer for first task\n")
      @async.sleep(20)
      root.add_defer(() => log.write_string("third group defer\n"))
      @async.sleep(20)
      log.write_string("first task finished\n")
    })
    root.spawn_bg(fn() {
      defer log.write_string("defer for second task\n")
      @async.sleep(10)
      root.add_defer(() => log.write_string("second group defer\n"))
      @async.sleep(20)
      log.write_string("second task finished\n")
    })
    root.spawn_bg(no_wait=true, fn() {
      defer log.write_string("defer for cancelled task\n")
      @async.sleep(1000)
    })
  })
  inspect(
    log.to_string(),
    content=(
      #|second task finished
      #|defer for second task
      #|first task finished
      #|defer for first task
      #|defer for cancelled task
      #|third group defer
      #|second group defer
      #|first group defer
      #|
    ),
  )
}

///|
test "group defer error" {
  let log = StringBuilder::new()
  log.write_object(
    try? @async.with_event_loop(fn(root) {
      root.add_defer(() => log.write_string("first group defer\n"))
      root.spawn_bg(fn() {
        defer log.write_string("defer for first task\n")
        @async.sleep(20)
        root.add_defer(() => log.write_string("third group defer\n"))
        @async.sleep(20)
        log.write_string("first task finished\n")
      })
      root.spawn_bg(fn() {
        defer log.write_string("defer for second task\n")
        @async.sleep(10)
        root.add_defer(() => log.write_string("second group defer\n"))
        @async.sleep(20)
        log.write_string("second task raise error\n")
        raise Err
      })
      root.spawn_bg(no_wait=true, fn() {
        defer log.write_string("defer for cancelled task\n")
        @async.sleep(1000)
      })
    }),
  )
  inspect(
    log.to_string(),
    content=(
      #|second task raise error
      #|defer for second task
      #|defer for first task
      #|defer for cancelled task
      #|third group defer
      #|second group defer
      #|first group defer
      #|Err(Err)
    ),
  )
}

///|
test "group defer cancelled" {
  let log = StringBuilder::new()
  @async.with_event_loop(fn(root) {
    root.spawn_bg(fn() {
      for _ in 0..<4 {
        @async.sleep(50)
        log.write_string("tick\n")
      }
    })
    @async.with_timeout(125, fn() {
      @async.with_task_group(fn(group) {
        group.add_defer(fn() {
          @async.protect_from_cancel(fn() {
            @async.sleep(50)
            log.write_string("protected async defer completed\n")
          })
        })
        group.add_defer(fn() {
          try @async.sleep(50) catch {
            err => {
              log.write_string("normal async defer cancelled with \{err}\n")
              raise err
            }
          } noraise {
            _ => log.write_string("normal async defer completed\n")
          }
        })
        defer log.write_string("start group termination\n")
        @async.sleep(1000)
      })
    })
    log.write_string("group terminated\n")
  })
  inspect(
    log.to_string(),
    content=(
      #|tick
      #|tick
      #|start group termination
      #|normal async defer cancelled with Cancelled
      #|tick
      #|protected async defer completed
      #|group terminated
      #|tick
      #|
    ),
  )
}
