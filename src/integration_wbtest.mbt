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
#cfg(target="wasm-gc")
test "wasm-gc async main drains cooperative tasks" {
  let log : Array[String] = []
  run_async_main(() => {
    with_task_group(group => {
      group.spawn_bg(() => {
        log.push("a1")
        pause()
        log.push("a2")
      })
      group.spawn_bg(() => {
        log.push("b1")
        pause()
        log.push("b2")
      })
    })
    log.push("done")
  })
  assert_eq(log, ["a1", "b1", "a2", "b2", "done"])
}

///|
#cfg(target="wasm-gc")
test "wasm-gc async main returns with suspended tasks and permits reentry" {
  let log : Array[String] = []
  let suspended = @coroutine.spawn(() => {
    log.push("waiting")
    @coroutine.suspend()
    log.push("resumed")
  })
  run_async_main(() => log.push("main"))
  assert_eq(log, ["waiting", "main"])
  suspended.wake()
  run_async_main(() => ())
  assert_eq(log, ["waiting", "main", "resumed"])
  guard! suspended.unwrap() is Continue
}
