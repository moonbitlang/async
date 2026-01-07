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
async test "retry immediate" {
  let log = StringBuilder::new()
  let mut i = 0
  @async.retry(Immediate, fn() {
    log.write_string("tick \{i}\n")
    i = i + 1
    if i < 3 {
      raise Err
    }
  })
  inspect(
    log.to_string(),
    content=(
      #|tick 0
      #|tick 1
      #|tick 2
      #|
    ),
  )
}

///|
async test "retry fixed" {
  let log = StringBuilder::new()
  @async.with_task_group(fn(root) {
    root.spawn_bg(fn() {
      for i in 0..<3 {
        @async.sleep(200)
        log.write_string("tick \{i}\n")
      }
    })
    @async.sleep(100)
    let mut i = 0
    @async.retry(FixedDelay(200), fn() {
      log.write_string("loop \{i}\n")
      i = i + 1
      if i < 3 {
        raise Err
      }
    })
  })
  inspect(
    log.to_string(),
    content=(
      #|loop 0
      #|tick 0
      #|loop 1
      #|tick 1
      #|loop 2
      #|tick 2
      #|
    ),
  )
}

///|
async test "retry exponential" {
  let log = StringBuilder::new()
  log.write_object(
    try? @async.with_task_group(fn(root) {
      root.spawn_bg(fn() {
        for i in 0..<7 {
          @async.sleep(200)
          log.write_string("tick \{i}\n")
        }
      })
      @async.sleep(100)
      let mut i = 0
      @async.retry(ExponentialDelay(initial=200, factor=2, maximum=600), fn() {
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
async test "retry cancelled1" {
  let log = StringBuilder::new()
  let mut i = 0
  @async.with_timeout(500, fn() {
    @async.retry(Immediate, fn() {
      @async.sleep(200)
      log.write_string("loop \{i}\n")
      i = i + 1
      raise Err
    })
  }) catch {
    @async.TimeoutError => ()
    err => raise err
  }
  inspect(
    log.to_string(),
    content=(
      #|loop 0
      #|loop 1
      #|
    ),
  )
}

///|
async test "retry cancelled2" {
  let log = StringBuilder::new()
  let mut i = 0
  @async.with_timeout(500, fn() {
    @async.retry(FixedDelay(200), fn() {
      log.write_string("loop \{i}\n")
      i = i + 1
      raise Err
    })
  }) catch {
    @async.TimeoutError => ()
    err => raise err
  }
  inspect(
    log.to_string(),
    content=(
      #|loop 0
      #|loop 1
      #|loop 2
      #|
    ),
  )
}

///|
async test "retry fatal_error" {
  let log = StringBuilder::new()
  fn fatal_error(err) {
    not(err is @async.TimeoutError)
  }

  let mut i = 0
  async fn worker() {
    log.write_string("worker run #\{i}\n")
    i = i + 1
    if i < 3 {
      @async.with_timeout(100, () => @async.sleep(1000))
    } else {
      raise Failure::Failure("fatal error")
    }
  }

  inspect(
    try? @async.retry(Immediate, fatal_error~, worker),
    content=(
      #|Err(Failure("fatal error"))
    ),
  )
  inspect(
    log.to_string(),
    content=(
      #|worker run #0
      #|worker run #1
      #|worker run #2
      #|
    ),
  )
}
