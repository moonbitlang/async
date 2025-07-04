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
test "spawn_bg basic" {
  let buf = StringBuilder::new()
  @async.with_event_loop(fn() {
    @async.spawn_bg(fn() {
      @async.sleep(100)
      buf.write_string("task 1, tick 1\n")
      @async.sleep(100)
      buf.write_string("task 1, tick 2\n")
      @async.sleep(100)
      buf.write_string("task 1, tick 3\n")
    })
    @async.spawn_bg(fn() {
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
test "spawn_bg error1" {
  let buf = StringBuilder::new()
  let result = try? @async.with_event_loop(fn() {
      @async.spawn_bg(fn() {
        @async.sleep(10000)
        buf.write_string("task 1 finished\n")
      })
      @async.spawn_bg(fn() {
        @async.sleep(100)
        raise Err
      })
    })
  buf.write_string(result.to_string())
  inspect(buf.to_string(), content="Err(Err)")
}

///|
test "spawn_bg error2" {
  let buf = StringBuilder::new()
  let result = try? @async.with_event_loop(fn() {
      @async.spawn_bg(fn() {
        @async.sleep(100)
        raise Err
      })
      @async.spawn_bg(fn() {
        @async.sleep(10000)
        buf.write_string("task 1 finished\n")
      })
    })
  buf.write_string(result.to_string())
  inspect(buf.to_string(), content="Err(Err)")
}
