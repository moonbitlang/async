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
test "wait2 ok" {
  let buf = StringBuilder::new()
  with_event_loop(fn() {
    let t1 = @async.spawn(fn() {
      @async.sleep(100)
      6
    })
    let t2 = @async.spawn(fn() {
      @async.sleep(200)
      7
    })
    let (x, y) = @async.wait2(t1, t2)
    buf.write_string("result: \{x * y}\n")
  })
  inspect(
    buf.to_string(),
    content=(
      #|result: 42
      #|
    ),
  )
}

///|
test "wait2 err1" {
  let buf = StringBuilder::new()
  with_event_loop(fn() {
    let t1 = @async.spawn(fn() {
      @async.sleep(100)
      raise Err
    })
    let t2 = @async.spawn(fn() {
      @async.sleep(200)
      buf.write_string("task 2 finished\n")
      7
    })
    try @async.wait2(t1, t2) catch {
      err => buf.write_string("received error \{err}\n")
    } noraise {
      (x, y) => buf.write_string("result: \{x * y}\n")
    }
  })
  inspect(
    buf.to_string(),
    content=(
      #|received error Err
      #|
    ),
  )
}

///|
test "wait2 err2" {
  let buf = StringBuilder::new()
  with_event_loop(fn() {
    let t1 = @async.spawn(fn() {
      @async.sleep(200)
      raise Err
    })
    let t2 = @async.spawn(fn() {
      @async.sleep(100)
      buf.write_string("task 2 finished\n")
      7
    })
    try @async.wait2(t1, t2) catch {
      err => buf.write_string("received error \{err}\n")
    } noraise {
      (x, y) => buf.write_string("result: \{x * y}\n")
    }
  })
  inspect(
    buf.to_string(),
    content=(
      #|task 2 finished
      #|received error Err
      #|
    ),
  )
}

///|
test "wait3 ok" {
  let buf = StringBuilder::new()
  with_event_loop(fn() {
    let t1 = @async.spawn(fn() {
      @async.sleep(100)
      6
    })
    let t2 = @async.spawn(fn() {
      @async.sleep(200)
      3
    })
    let t3 = @async.spawn(fn() {
      @async.sleep(300)
      4
    })
    let (x, y, z) = @async.wait3(t1, t2, t3)
    buf.write_string("result: \{x * (y + z)}\n")
  })
  inspect(
    buf.to_string(),
    content=(
      #|result: 42
      #|
    ),
  )
}

///|
test "wait3 err" {
  let buf = StringBuilder::new()
  with_event_loop(fn() {
    let t1 = @async.spawn(fn() {
      @async.sleep(100)
      buf.write_string("task 1 finished\n")
      6
    })
    let t2 = @async.spawn(fn() {
      @async.sleep(200)
      raise Err
    })
    let t3 = @async.spawn(fn() {
      @async.sleep(300)
      buf.write_string("task 3 finished\n")
      4
    })
    try @async.wait3(t1, t2, t3) catch {
      err => buf.write_string("received error \{err}\n")
    } noraise {
      (x, y, z) => buf.write_string("result: \{x * (y + z)}\n")
    }
  })
  inspect(
    buf.to_string(),
    content=(
      #|task 1 finished
      #|received error Err
      #|
    ),
  )
}

///|
test "wait4 ok" {
  let buf = StringBuilder::new()
  with_event_loop(fn() {
    let t1 = @async.spawn(fn() {
      @async.sleep(100)
      6
    })
    let t2 = @async.spawn(fn() {
      @async.sleep(200)
      13
    })
    let t3 = @async.spawn(fn() {
      @async.sleep(300)
      2
    })
    let t4 = @async.spawn(fn() {
      @async.sleep(400)
      3
    })
    let (x, y, z, w) = @async.wait4(t1, t2, t3, t4)
    buf.write_string("result: \{x * (y - z * w)}\n")
  })
  inspect(
    buf.to_string(),
    content=(
      #|result: 42
      #|
    ),
  )
}

///|
test "wait4 err" {
  let buf = StringBuilder::new()
  with_event_loop(fn() {
    let t1 = @async.spawn(fn() {
      @async.sleep(100)
      buf.write_string("task 1 finished\n")
      6
    })
    let t2 = @async.spawn(fn() {
      @async.sleep(200)
      buf.write_string("task 2 finished\n")
      13
    })
    let t3 = @async.spawn(fn() {
      @async.sleep(300)
      raise Err
    })
    let t4 = @async.spawn(fn() {
      @async.sleep(400)
      buf.write_string("task 4 finished\n")
      3
    })
    try @async.wait4(t1, t2, t3, t4) catch {
      err => buf.write_string("received error \{err}\n")
    } noraise {
      (x, y, z, w) => buf.write_string("result: \{x * (y - z * w)}\n")
    }
  })
  inspect(
    buf.to_string(),
    content=(
      #|task 1 finished
      #|task 2 finished
      #|received error Err
      #|
    ),
  )
}
