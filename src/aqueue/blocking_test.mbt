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
async test "blocking unbuffered" {
  let log = []
  @async.with_task_group(group => {
    let q = @async.Queue::new(kind=Blocking(1))
    group.spawn_bg(() => for i in 0..<3 {
      q.put(i)
      log.push("put(\{i})")
    })
    group.spawn_bg(() => for _ in 0..<3 {
      let x = q.get()
      log.push("get() => \{x}")
      @async.sleep(100)
    })
  })
  @json.inspect(log, content=[
    "put(0)", "get() => 0", "put(1)", "get() => 1", "put(2)", "get() => 2",
  ])
}

///|
async test "blocking buffered" {
  let log = []
  @async.with_task_group(group => {
    let q = @async.Queue::new(kind=Blocking(2))
    group.spawn_bg(() => for i in 0..<4 {
      q.put(i)
      log.push("put(\{i})")
    })
    group.spawn_bg(() => for _ in 0..<4 {
      let x = q.get()
      log.push("get() => \{x}")
      @async.sleep(100)
    })
  })
  @json.inspect(log, content=[
    "put(0)", "put(1)", "get() => 0", "put(2)", "get() => 1", "put(3)", "get() => 2",
    "get() => 3",
  ])
}

///|
async test "blocking fairness" {
  let log = []
  @async.with_task_group(group => {
    let q = @async.Queue::new(kind=Blocking(1))
    q.put(0)
    group.spawn_bg(() => for i in 0..<3 {
      q.put(i)
      log.push("task 1 put(\{i})")
    })
    group.spawn_bg(() => for i in 0..<3 {
      q.put(i)
      log.push("task 2 put(\{i})")
    })
    group.spawn_bg(no_wait=true, () => for {
      @async.sleep(100)
      ignore(q.get())
    })
  })
  @json.inspect(log, content=[
    "task 1 put(0)", "task 2 put(0)", "task 1 put(1)", "task 2 put(1)", "task 1 put(2)",
    "task 2 put(2)",
  ])
}

///|
async test "blocking cancellation" {
  let log = []
  @async.with_task_group(group => {
    let q = @async.Queue::new(kind=Blocking(1))
    q.put(0)
    group.spawn_bg(no_wait=true, () => for {
      @async.sleep(200)
      ignore(q.get())
    })
    @async.with_timeout(500, () => for {
      q.put(0) catch {
        err => {
          log.push("put() cancelled")
          raise err
        }
      }
      log.push("put() completed")
    }) catch {
      @async.TimeoutError => ()
      err => raise err
    }
  })
  @json.inspect(log, content=[
    "put() completed", "put() completed", "put() cancelled",
  ])
}

///|
async test "blocking fairness2" {
  let log = []
  @async.with_task_group(fn(root) {
    let queue = @aqueue.Queue::new(kind=Blocking(1))
    queue.put(0)
    root.spawn_bg(fn() {
      for i in 0..<2 {
        queue.put(i)
        log.push("task 1: put() completed")
        @async.sleep(200)
        let x = queue.get()
        log.push("task 1: get() => \{x}")
      }
    })
    root.spawn_bg(fn() {
      @async.sleep(100)
      for i in 0..<2 {
        queue.put(i)
        log.push("task 2: put() completed")
        @async.sleep(200)
        let x = queue.get()
        log.push("task 2: get() => \{x}")
      }
    })
    @async.sleep(200)
    inspect(queue.get(), content="0")
  })
  @json.inspect(log, content=[
    "task 1: put() completed", "task 1: get() => 0", "task 2: put() completed", "task 2: get() => 0",
    "task 1: put() completed", "task 1: get() => 1", "task 2: put() completed", "task 2: get() => 1",
  ])
}

///|
async test "blocking immediate cancellation" {
  let log = []
  @async.with_task_group(group => {
    let q = @async.Queue::new(kind=Blocking(1))
    q.put(0)
    let put_task = group.spawn(allow_failure=true, () => {
      q.put(1) catch {
        err => {
          log.push("put() cancelled")
          raise err
        }
      }
      log.push("put() completed")
    })
    @async.sleep(100)
    let _ = q.get()
    put_task.cancel()
    @async.sleep(100)
    inspect(q.try_get(), content="Some(1)")
  })
  @json.inspect(log, content=["put() completed"])
}

///|
test "blocking try_put" {
  let q = @aqueue.Queue::new(kind=Blocking(3))
  inspect(q.try_put(0), content="true")
  inspect(q.try_put(1), content="true")
  inspect(q.try_put(2), content="true")
  inspect(q.try_put(3), content="false")
  // the last `put` should have no effect
  for i in 0..<3 {
    assert_eq(q.try_get(), Some(i))
  }
  inspect(q.try_get(), content="None")
  // `put` again
  inspect(q.try_put(0), content="true")
  inspect(q.try_put(1), content="true")
  inspect(q.try_put(2), content="true")
  inspect(q.try_put(3), content="false")
  inspect(q.try_get(), content="Some(0)")
  inspect(q.try_put(3), content="true")
  inspect(q.try_put(4), content="false")
}
