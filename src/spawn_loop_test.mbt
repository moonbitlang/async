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
test "spawn_loop basic" {
  let log = StringBuilder::new()
  log.write_object(
    try? @async.with_event_loop(fn(root) {
      let mut i = 0
      root.spawn_loop(fn() {
        log.write_string("tick \{i}\n")
        i = i + 1
        if i < 3 {
          IterContinue
        } else {
          IterEnd
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
test "spawn_loop basic-error" {
  let log = StringBuilder::new()
  log.write_object(
    try? @async.with_event_loop(fn(root) {
      let mut i = 0
      root.spawn_loop(fn() {
        log.write_string("tick \{i}\n")
        i = i + 1
        if i >= 3 {
          raise Err
        }
        IterContinue
      })
    }),
  )
  inspect(
    log.to_string(),
    content=(
      #|tick 0
      #|tick 1
      #|tick 2
      #|Err(Err)
    ),
  )
}

///|
test "spawn_loop retry-immediate" {
  let log = StringBuilder::new()
  log.write_object(
    try? @async.with_event_loop(fn(root) {
      let mut i = 0
      root.spawn_loop(retry=Immediate, fn() {
        log.write_string("tick \{i}\n")
        i = i + 1
        if i < 3 {
          raise Err
        }
        IterEnd
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
test "spawn_loop retry-fixed" {
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
      root.spawn_loop(retry=FixedDelay(50), fn() {
        log.write_string("loop \{i}\n")
        i = i + 1
        if i < 3 {
          raise Err
        }
        IterEnd
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
test "spawn_loop retry-exponential" {
  let log = StringBuilder::new()
  log.write_object(
    try? @async.with_event_loop(fn(root) {
      root.spawn_bg(fn() {
        for i in 0..<9 {
          @async.sleep(50)
          log.write_string("tick \{i}\n")
        }
      })
      @async.sleep(25)
      let mut i = 0
      root.spawn_loop(
        retry=ExponentialDelay(initial=50, factor=2, maximum=150),
        fn() {
          log.write_string("loop \{i}\n")
          i = i + 1
          match i {
            1 | 2 | 3 => raise Err
            4 => IterContinue
            5 | 6 => raise Err
            _ => IterEnd
          }
        },
      )
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
      #|loop 4
      #|tick 6
      #|loop 5
      #|tick 7
      #|tick 8
      #|loop 6
      #|Ok(())
    ),
  )
}

///|
test "spawn_loop cancelled1" {
  let log = StringBuilder::new()
  log.write_object(
    try? @async.with_event_loop(fn(root) {
      let mut i = 0
      root.spawn_loop(no_wait=true, allow_failure=true, retry=Immediate, fn() {
        @async.sleep(50)
        log.write_string("loop \{i}\n")
        i = i + 1
        IterContinue
      })
      @async.sleep(125)
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
test "spawn_loop cancelled2" {
  let log = StringBuilder::new()
  log.write_object(
    try? @async.with_event_loop(fn(root) {
      let mut i = 0
      root.spawn_loop(no_wait=true, allow_failure=true, retry=FixedDelay(50), () => {
        log.write_string("loop \{i}\n")
        i = i + 1
        raise Err
      })
      @async.sleep(125)
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
