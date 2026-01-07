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
async test "manual cancel" {
  let buf = StringBuilder::new()
  let result = try? @async.with_task_group(fn(root) {
    let task = root.spawn(allow_failure=true, fn() {
      try {
        @async.sleep(300)
        buf.write_string("task finished\n")
      } catch {
        err => {
          buf.write_string("cancelled by error \{err}\n")
          raise err
        }
      }
    })
    @async.sleep(100)
    task.cancel()
    @async.sleep(200)
    buf.write_string("main task exit\n")
  })
  buf.write_string(result.to_string())
  inspect(
    buf.to_string(),
    content=(
      #|cancelled by error Cancelled
      #|main task exit
      #|Ok(())
    ),
  )
}

///|
suberror Err derive(Show)

///|
async test "error propagation" {
  let buf = StringBuilder::new()
  let result = try? @async.with_task_group(fn(root) {
    root.spawn_bg(fn() {
      @async.sleep(300)
      raise Err
    })
    root.spawn_bg(fn() {
      try {
        @async.sleep(200)
        buf.write_string("task 2, tick 1\n")
        @async.sleep(200)
        buf.write_string("task 2, tick 2\n")
      } catch {
        err => {
          buf.write_string("task 2 cancelled with error \{err}\n")
          raise err
        }
      } noraise {
        _ => buf.write_string("task 2 normal exit\n")
      }
    })
  })
  buf.write_string(result.to_string())
  inspect(
    buf.to_string(),
    content=(
      #|task 2, tick 1
      #|task 2 cancelled with error Cancelled
      #|Err(Err)
    ),
  )
}

///|
async test "multiple scope" {
  let buf = StringBuilder::new()
  @async.with_task_group(fn(root) {
    root.spawn_bg(fn() {
      try
        @async.with_task_group(fn(ctx) {
          ctx.spawn_bg(fn() {
            @async.sleep(200)
            raise Err
          })
          ctx.spawn_bg(fn() {
            try @async.sleep(400) catch {
              err => {
                buf.write_string("ctx 1 task 2 cancelled with \{err}\n")
                raise err
              }
            } noraise {
              _ => buf.write_string("ctx 1 task 2 finished\n")
            }
          })
        })
      catch {
        err => buf.write_string("ctx 1 received error \{err}\n")
      } noraise {
        _ => buf.write_string("ctx 1 finished normally\n")
      }
    })
    root.spawn_bg(fn() {
      try
        @async.with_task_group(fn(ctx) {
          ctx.spawn_bg(fn() {
            @async.sleep(500)
            raise Err
          })
          ctx.spawn_bg(fn() {
            try @async.sleep(300) catch {
              err => {
                buf.write_string("ctx 2 task 2 cancelled with \{err}\n")
                raise err
              }
            } noraise {
              _ => buf.write_string("ctx 2 task 2 finished\n")
            }
          })
        })
      catch {
        err => buf.write_string("ctx 2 received error \{err}\n")
      } noraise {
        _ => buf.write_string("ctx 2 finished normally\n")
      }
    })
  })
  inspect(
    buf.to_string(),
    content=(
      #|ctx 1 task 2 cancelled with Cancelled
      #|ctx 1 received error Err
      #|ctx 2 task 2 finished
      #|ctx 2 received error Err
      #|
    ),
  )
}

///|
async test "recursive cancel" {
  let buf = StringBuilder::new()
  buf.write_object(
    try? @async.with_task_group(fn(root) {
      root.spawn_bg(fn() {
        for _ in 0..<2 {
          @async.sleep(400)
          buf.write_string("tick\n")
        }
      })
      let task = root.spawn(allow_failure=true, fn() {
        @async.sleep(1000) catch {
          err => buf.write_string("first sleep cancelled with \{err}\n")
        }
        @async.sleep(1000) catch {
          err => buf.write_string("second sleep cancelled with \{err}\n")
        }
        buf.write_string("task finished\n")
      })
      @async.sleep(600)
      task.cancel()
      buf.write_string("main task exit\n")
    }),
  )
  inspect(
    buf.to_string(),
    content=(
      #|tick
      #|main task exit
      #|first sleep cancelled with Cancelled
      #|second sleep cancelled with Cancelled
      #|task finished
      #|tick
      #|Ok(())
    ),
  )
}

///|
async test "spawn directly error" {
  let buf = StringBuilder::new()
  buf.write_object(
    try? @async.with_task_group(fn(root) {
      root.spawn_bg(fn() {
        @async.with_task_group(fn(group) {
          @async.sleep(1)
          group.spawn_bg(() => raise Err)
          buf.write_string("after spawn\n")
          @async.sleep(400)
          buf.write_string("main task exit\n")
        })
      })
      @async.sleep(200)
    }),
  )
  inspect(
    buf.to_string(),
    content=(
      #|after spawn
      #|Err(Err)
    ),
  )
}

///|
async test "error in cancellation" {
  let log = StringBuilder::new()
  log.write_object(
    try? @async.with_task_group(fn(root) {
      root.spawn_bg(no_wait=true, fn() {
        @async.sleep(1000) catch {
          _ => {
            log.write_string("causing other error in cancellation handler\n")
            raise Err
          }
        }
      })
      @async.sleep(200)
    }),
  )
  inspect(
    log.to_string(),
    content=(
      #|causing other error in cancellation handler
      #|Err(Err)
    ),
  )
}

///|
async test "immediately cancelled" {
  let log = StringBuilder::new()
  @async.with_task_group(fn(root) {
    let task = root.spawn(allow_failure=true, fn() {
      defer log.write_string("task terminated\n")
      log.write_string("task started\n")
      @async.sleep(100)
      log.write_string("task finished\n")
    })
    log.write_string("task spawned\n")
    task.cancel()
  })
  inspect(
    log.to_string(),
    content=(
      #|task spawned
      #|task started
      #|task terminated
      #|
    ),
  )
}

///|
async test "immediate failure" {
  let result = try? @async.with_task_group(group => {
    group.spawn_bg(() => raise Failure::Failure("failure"))
    group.spawn_bg(() => group.spawn_bg(() => @async.sleep(100)))
  })
  inspect(
    result,
    content=(
      #|Err(Failure("failure"))
    ),
  )
}
