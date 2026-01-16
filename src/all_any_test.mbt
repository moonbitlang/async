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
async test "all basic" {
  let results = @async.all([
    fn() {
      @async.sleep(100)
      1
    },
    fn() {
      @async.sleep(50)
      2
    },
    fn() { 3 },
  ])
  @json.inspect(results, content=[1, 2, 3])
}

///|
async test "all preserves order" {
  let log = StringBuilder::new()
  let results = @async.all([
    fn() {
      @async.sleep(300)
      log.write_string("task 0\n")
      0
    },
    fn() {
      @async.sleep(100)
      log.write_string("task 1\n")
      1
    },
    fn() {
      log.write_string("task 2\n")
      2
    },
  ])
  inspect(
    log.to_string(),
    content=(
      #|task 2
      #|task 1
      #|task 0
      #|
    ),
  )
  @json.inspect(results, content=[0, 1, 2])
}

///|
async test "all with max_concurrent" {
  let mut running = 0
  let results = try? @async.all(
    [
      fn() {
        running += 1
        defer {
          running -= 1
        }
        assert_true(running <= 2)
        @async.sleep(200)
        0
      },
      fn() {
        running += 1
        defer {
          running -= 1
        }
        assert_true(running <= 2)
        @async.sleep(200)
        1
      },
      fn() {
        running += 1
        defer {
          running -= 1
        }
        assert_true(running <= 2)
        @async.sleep(200)
        2
      },
    ],
    max_concurrent=2,
  )
  @json.inspect(results, content={ "Ok": [0, 1, 2] })
}

///|
async test "all empty" {
  let results : Array[Int] = @async.all([])
  @json.inspect(results, content=[])
}

///|
async test "all single task" {
  let result = @async.all([fn() { 42 }])
  @json.inspect(result, content=[42])
}

///|
async test "all failure propagates" {
  let success = []
  try
    @async.all([
      fn() {
        @async.sleep(100)
        success.push(0)
      },
      fn() {
        @async.sleep(50)
        success.push(1)
        raise Failure::Failure("Err")
      },
      fn() {
        @async.sleep(200)
        success.push(2)
      },
    ])
  catch {
    Failure::Failure(msg) => {
      assert_eq(msg, "Err")
      inspect(success, content="[1]")
    }
    _ => fail("Should have raised Failure")
  } noraise {
    _ => fail("Should have raised Failure")
  }
}

///|
async test "any basic" {
  let result = @async.any([
    fn() {
      @async.sleep(300)
      1
    },
    fn() {
      @async.sleep(100)
      2
    },
    fn() {
      @async.sleep(200)
      3
    },
  ])
  @json.inspect(result, content=2)
}

///|
async test "any returns first success" {
  let log = StringBuilder::new()
  let result = @async.any([
    fn() {
      @async.sleep(300)
      log.write_string("task 0\n")
      0
    },
    fn() {
      @async.sleep(100)
      log.write_string("task 1\n")
      1
    },
    fn() {
      @async.sleep(200)
      log.write_string("task 2\n")
      2
    },
  ])
  inspect(
    log.to_string(),
    content=(
      #|task 1
      #|
    ),
  )
  @json.inspect(result, content=1)
}

// TODO: Fix this test - there seems to be an issue with the implementation
// when tasks fail, "trying to spawn from a terminated task group" error occurs

///|
async test "any failure without allow_failure" {
  let log = StringBuilder::new()
  try
    @async.any([
      fn() {
        @async.sleep(100)
        log.write_string("task 0\n")
      },
      fn() {
        @async.sleep(50)
        raise Failure::Failure("Err")
      },
    ])
  catch {
    Failure::Failure(msg) => assert_eq(msg, "Err")
    _ => fail("Should have raised Failure")
  } noraise {
    _ => fail("Should have raised Failure")
  }
}

///|
async test "any with allow_failure" {
  let log = StringBuilder::new()
  let result = @async.any(
    [
      fn() {
        @async.sleep(100)
        log.write_string("task 0\n")
        raise Err
      },
      fn() {
        @async.sleep(50)
        log.write_string("task 1\n")
        raise Failure::Failure("fail")
      },
      fn() {
        @async.sleep(150)
        log.write_string("task 2\n")
        2
      },
    ],
    allow_failure=true,
  )
  inspect(
    log.to_string(),
    content=(
      #|task 1
      #|task 0
      #|task 2
      #|
    ),
  )
  @json.inspect(result, content=2)
}

///|
async test "any single task" {
  let result = @async.any([fn() { 42 }])
  @json.inspect(result, content=42)
}

///|
async test "any empty fails" {
  try @async.any(Array::make(0, () => ())) catch {
    Failure::Failure(_) => ()
    _ => fail("Should have raised Failure")
  } noraise {
    _ => fail("Should have raised Failure")
  }
}

///|
async test "any all fail without allow_failure" {
  try
    @async.any([
      fn() {
        @async.sleep(100)
        0
      },
      fn() {
        @async.sleep(50)
        raise Failure::Failure("error 1")
      },
    ])
  catch {
    Failure::Failure(msg) => assert_eq(msg, "error 1")
    _ => fail("Should have raised error 1")
  } noraise {
    _ => fail("Should have raised error 1")
  }
}

///|
async test "any all fail with allow_failure" {
  let log = StringBuilder::new()
  @async.any(
    [
      fn() {
        @async.sleep(100)
        log.write_string("task 0\n")
        raise Failure::Failure("error 0")
      },
      fn() {
        @async.sleep(50)
        log.write_string("task 1\n")
        raise Failure::Failure("error 1")
      },
    ],
    allow_failure=true,
  ) catch {
    Failure::Failure(msg) => log.write_string("caught: \{msg}\n")
    _ => log.write_string("caught other error\n")
  }
  inspect(
    log.to_string(),
    content=(
      #|task 1
      #|task 0
      #|caught: error 0
      #|
    ),
  )
}
