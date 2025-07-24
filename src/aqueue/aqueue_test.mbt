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
test "aqueue basic" {
  let log = StringBuilder::new()
  @async.with_event_loop(fn(root) {
    let queue = @aqueue.Queue::new()
    root.spawn_bg(fn() {
      for _ in 0..<6 {
        log.write_string("get => \{queue.get()}\n")
      }
    })
    root.spawn_bg(fn() {
      for x in 0..<6 {
        @async.sleep(20)
        queue.put(x)
        log.write_string("put(\{x})\n")
      }
    })
  })
  inspect(
    log.to_string(),
    content=(
      #|put(0)
      #|get => 0
      #|put(1)
      #|get => 1
      #|put(2)
      #|get => 2
      #|put(3)
      #|get => 3
      #|put(4)
      #|get => 4
      #|put(5)
      #|get => 5
      #|
    ),
  )
}

///|
test "aqueue multi-reader" {
  let log = StringBuilder::new()
  @async.with_event_loop(fn(root) {
    let queue = @aqueue.Queue::new()
    root.spawn_bg(fn() {
      @async.sleep(20)
      let x = queue.get()
      log.write_string("task 1: get => \{x}\n")
    })
    root.spawn_bg(fn() {
      let x = queue.get()
      log.write_string("task 2: get => \{x}\n")
    })
    @async.sleep(50)
    queue.put(1)
    queue.put(2)
  })
  inspect(
    log.to_string(),
    content=(
      #|task 2: get => 1
      #|task 1: get => 2
      #|
    ),
  )
}

///|
test "aqueue cancellation" {
  let log = StringBuilder::new()
  @async.with_event_loop(fn(root) {
    let queue = @aqueue.Queue::new()
    root.spawn_bg(fn() {
      for x in 0..<6 {
        @async.sleep(50)
        log.write_string("put(\{x})\n")
        queue.put(x)
      }
    })
    @async.with_timeout(225, fn() {
      for {
        let x = queue.get() catch {
          err => {
            log.write_string("`queue.get()` cancelled with \{err}\n")
            raise err
          }
        }
        log.write_string("get => \{x}\n")
      }
    })
  })
  inspect(
    log.to_string(),
    content=(
      #|put(0)
      #|get => 0
      #|put(1)
      #|get => 1
      #|put(2)
      #|get => 2
      #|put(3)
      #|get => 3
      #|`queue.get()` cancelled with Cancelled
      #|put(4)
      #|put(5)
      #|
    ),
  )
}

///|
test "aqueue fairness" {
  let log = StringBuilder::new()
  @async.with_event_loop(fn(root) {
    let queue = @aqueue.Queue::new()
    root.spawn_bg(fn() {
      for _ in 0..<2 {
        let x = queue.get()
        log.write_string("task 1: get => \{x}\n")
      }
    })
    root.spawn_bg(fn() {
      for _ in 0..<2 {
        let x = queue.get()
        log.write_string("task 2: get => \{x}\n")
      }
    })
    @async.sleep(20)
    queue.put(1)
    queue.put(2)
    @async.sleep(20)
    queue.put(3)
    queue.put(4)
  })
  inspect(
    log.to_string(),
    content=(
      #|task 1: get => 1
      #|task 2: get => 2
      #|task 1: get => 3
      #|task 2: get => 4
      #|
    ),
  )
}
