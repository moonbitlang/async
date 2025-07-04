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
test "main_task_exit" {
  let buf = StringBuilder::new()
  @async.with_event_loop(fn() {
    let _ = @async.spawn(fn() {
      try {
        @async.sleep(1000)
        buf.write_string("task finished\n")
      } catch {
        err => {
          buf.write_string("cancelled by error \{err}\n")
          raise err
        }
      }
    })
    @async.sleep(500)
    buf.write_string("main task exit\n")
  })
  inspect(
    buf.to_string(),
    content=(
      #|main task exit
      #|cancelled by error Cancelled
      #|
    ),
  )
}

///|
test "manual cancel" {
  let buf = StringBuilder::new()
  @async.with_event_loop(fn() {
    let task = @async.spawn(fn() {
      try {
        @async.sleep(500)
        buf.write_string("task finished\n")
      } catch {
        err => {
          buf.write_string("cancelled by error \{err}\n")
          raise err
        }
      }
    })
    task.cancel()
    @async.sleep(1000)
    buf.write_string("main task exit\n")
  })
  inspect(
    buf.to_string(),
    content=(
      #|cancelled by error Cancelled
      #|main task exit
      #|
    ),
  )
}

///|
suberror Err derive(Show)

///|
test "error propagation" {
  let buf = StringBuilder::new()
  @async.with_event_loop(fn() {
    let task1 = @async.spawn(fn() {
      @async.sleep(1000)
      raise Err
    })
    let task2 = @async.spawn(fn() {
      try {
        @async.sleep(500)
        buf.write_string("task 2, tick 1\n")
        @async.sleep(1000)
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
    try {
      task1.wait()
      task2.wait()
    } catch {
      err => buf.write_string("main task received error \{err}\n")
    } noraise {
      _ => buf.write_string("main task normal exit\n")
    }
  })
  inspect(
    buf.to_string(),
    content=(
      #|task 2, tick 1
      #|main task received error Err
      #|task 2 cancelled with error Cancelled
      #|
    ),
  )
}

///|
test "multiple scope" {
  let buf = StringBuilder::new()
  with_event_loop(fn() {
    let outer1 = @async.spawn(fn() {
      let inner1 = @async.spawn(fn() {
        sleep(500)
        raise Err
      })
      let inner2 = @async.spawn(fn() {
        try sleep(1000) catch {
          err => {
            buf.write_string("ctx 1 task 2 cancelled with \{err}\n")
            raise err
          }
        } noraise {
          _ => buf.write_string("ctx 1 task 2 finished\n")
        }
      })
      try {
        inner1.wait()
        inner2.wait()
      } catch {
        err => buf.write_string("ctx 1 received error \{err}\n")
      } noraise {
        _ => buf.write_string("ctx 1 finished normally\n")
      }
    })
    let outer2 = @async.spawn(fn() {
      let inner1 = @async.spawn(fn() {
        sleep(2000)
        raise Err
      })
      let inner2 = @async.spawn(fn() {
        try sleep(1000) catch {
          err => {
            buf.write_string("ctx 2 task 2 cancelled with \{err}\n")
            raise err
          }
        } noraise {
          _ => buf.write_string("ctx 2 task 2 finished\n")
        }
      })
      try {
        inner1.wait()
        inner2.wait()
      } catch {
        err => buf.write_string("ctx 2 received error \{err}\n")
      } noraise {
        _ => buf.write_string("ctx 2 finished normally\n")
      }
    })
    outer1.wait()
    outer2.wait()
  })
  inspect(
    buf.to_string(),
    content=(
      #|ctx 1 received error Err
      #|ctx 1 task 2 cancelled with Cancelled
      #|ctx 2 task 2 finished
      #|ctx 2 received error Err
      #|
    ),
  )
}
