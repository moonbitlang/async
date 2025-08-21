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
test "retry immediate" {
  let log = StringBuilder::new()
  log.write_object(
    try? @async.with_event_loop(fn(_) {
      let mut i = 0
      retry(Immediate, fn() {
        log.write_string("tick \{i}\n")
        i = i + 1
        if i < 3 {
          raise Err
        }
      })
    }),
  )
  inspect(
    log.to_string(),
    content=(
      #|tick 0
      #|tick 1
      #|tick 2
      #|Ok(())
    ),
  )
}

///|
test "retry fixed" {
  let log = StringBuilder::new()
  log.write_object(
    try? @async.with_event_loop(fn(root) {
      root.spawn_bg(fn() {
        for i in 0..<3 {
          @async.sleep(50)
          log.write_string("tick \{i}\n")
        }
      })
      @async.sleep(25)
      let mut i = 0
      retry(FixedDelay(50), fn() {
        log.write_string("loop \{i}\n")
        i = i + 1
        if i < 3 {
          raise Err
        }
      })
    }),
  )
  inspect(
    log.to_string(),
    content=(
      #|loop 0
      #|tick 0
      #|loop 1
      #|tick 1
      #|loop 2
      #|tick 2
      #|Ok(())
    ),
  )
}

///|
test "retry exponential" {
  let log = StringBuilder::new()
  log.write_object(
    try? @async.with_event_loop(fn(root) {
      root.spawn_bg(fn() {
        for i in 0..<7 {
          @async.sleep(50)
          log.write_string("tick \{i}\n")
        }
      })
      @async.sleep(25)
      let mut i = 0
      retry(ExponentialDelay(initial=50, factor=2, maximum=150), fn() {
        log.write_string("loop \{i}\n")
        i = i + 1
        if i < 4 {
          raise Err
        }
      })
      log.write_string("retry completed\n")
    }),
  )
  inspect(
    log.to_string(),
    content=(
      #|loop 0
      #|tick 0
      #|loop 1
      #|tick 1
      #|tick 2
      #|loop 2
      #|tick 3
      #|tick 4
      #|tick 5
      #|loop 3
      #|retry completed
      #|tick 6
      #|Ok(())
    ),
  )
}

///|
test "retry cancelled1" {
  let log = StringBuilder::new()
  log.write_object(
    try? @async.with_event_loop(fn(_) {
      let mut i = 0
      @async.with_timeout(140, fn() {
        @async.retry(Immediate, fn() {
          @async.sleep(50)
          log.write_string("loop \{i}\n")
          i = i + 1
          raise Err
        })
      })
    }),
  )
  inspect(
    log.to_string(),
    content=(
      #|loop 0
      #|loop 1
      #|Ok(())
    ),
  )
}

///|
test "retry cancelled2" {
  let log = StringBuilder::new()
  log.write_object(
    try? @async.with_event_loop(fn(_) {
      let mut i = 0
      @async.with_timeout(125, fn() {
        retry(FixedDelay(50), fn() {
          log.write_string("loop \{i}\n")
          i = i + 1
          raise Err
        })
      })
    }),
  )
  inspect(
    log.to_string(),
    content=(
      #|loop 0
      #|loop 1
      #|loop 2
      #|Ok(())
    ),
  )
}
