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
async test "spawn_loop basic" {
  let log = StringBuilder::new()
  log.write_object(
    try? @async.with_task_group(fn(root) {
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
async test "spawn_loop basic-error" {
  let log = StringBuilder::new()
  log.write_object(
    try? @async.with_task_group(fn(root) {
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
async test "spawn_loop retry-exponential" {
  let log = StringBuilder::new()
  log.write_object(
    try? @async.with_task_group(fn(root) {
      root.spawn_bg(fn() {
        for i in 0..<9 {
          @async.sleep(200)
          log.write_string("tick \{i}\n")
        }
      })
      @async.sleep(100)
      let mut i = 0
      root.spawn_loop(
        retry=ExponentialDelay(initial=200, factor=2, maximum=600),
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
