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
test "spawn basic" {
  let buf = StringBuilder::new()
  @async.with_event_loop(fn(root) {
    root.spawn_bg(fn() {
      @async.sleep(100)
      buf.write_string("task 1, tick 1\n")
      @async.sleep(100)
      buf.write_string("task 1, tick 2\n")
      @async.sleep(100)
      buf.write_string("task 1, tick 3\n")
    })
    root.spawn_bg(fn() {
      @async.sleep(150)
      buf.write_string("task 2, tick 1\n")
      @async.sleep(100)
      buf.write_string("task 2, tick 2\n")
      @async.sleep(100)
      buf.write_string("task 2, tick 3\n")
    })
  })
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

///|
test "spawn error1" {
  let buf = StringBuilder::new()
  let result = try? @async.with_event_loop(fn(root) {
      root.spawn_bg(fn() {
        @async.sleep(10000)
        buf.write_string("task 1 finished\n")
      })
      root.spawn_bg(fn() {
        @async.sleep(100)
        raise Err
      })
    })
  buf.write_string(result.to_string())
  inspect(buf.to_string(), content="Err(Err)")
}

///|
test "spawn error2" {
  let buf = StringBuilder::new()
  let result = try? @async.with_event_loop(fn(root) {
      root.spawn_bg(fn() {
        @async.sleep(100)
        raise Err
      })
      root.spawn_bg(fn() {
        @async.sleep(10000)
        buf.write_string("task 1 finished\n")
      })
    })
  buf.write_string(result.to_string())
  inspect(buf.to_string(), content="Err(Err)")
}

///|
test "spawn after cancelled 1" {
  let buf = StringBuilder::new()
  buf.write_object(
    try? @async.with_event_loop(fn(root) {
      root.spawn_bg(fn() {
        try {
          @async.sleep(500)
          buf.write_string("task finished\n")
        } catch {
          err => {
            buf.write_string("cancelled by error \{err}\n")
            root.spawn_bg(() => @async.sleep(1000)) catch {
              err => buf.write_string("trying to spawn, received \{err}\n")
            }
            raise err
          }
        }
      })
      @async.sleep(100)
      raise Err
    }),
  )
  inspect(
    buf.to_string(),
    content=(
      #|cancelled by error Cancelled
      #|trying to spawn, received AlreadyTerminated
      #|Err(Err)
    ),
  )
}

///|
test "spawn after cancelled 2" {
  let buf = StringBuilder::new()
  buf.write_object(
    try? @async.with_event_loop(fn(root) {
      root.spawn_bg(no_wait=true, allow_failure=true, fn() {
        try {
          @async.sleep(1000)
          buf.write_string("task finished\n")
        } catch {
          err => {
            buf.write_string("cancelled by error \{err}\n")
            root.spawn_bg(() => @async.sleep(1000)) catch {
              err => buf.write_string("trying to spawn, received \{err}\n")
            }
            raise err
          }
        }
      })
      @async.sleep(500)
    }),
  )
  inspect(
    buf.to_string(),
    content=(
      #|cancelled by error Cancelled
      #|trying to spawn, received AlreadyTerminated
      #|Ok(())
    ),
  )
}
