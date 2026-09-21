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
async test "cancelled waiters stay bounded behind a live waiter" {
  let cond = Cond()
  @async.with_task_group(group => {
    let live = group.spawn(() => cond.wait())
    @async.sleep(0)
    for _ in 0..<1000 {
      let task = group.spawn(() => cond.wait())
      @async.sleep(0)
      task.cancel()
      task.wait() catch {
        @async.TaskCancelled => ()
        err => raise err
      }
    }
    assert_true(cond.waiters.length() <= 65)
    cond.signal()
    live.wait()
    cond.broadcast()
    assert_eq(cond.waiters.length(), 0)
  })
}

///|
async test "compacting cancelled waiters preserves signal order" {
  let cond = Cond()
  let woke : Array[Int] = []
  @async.with_task_group(group => {
    for i in 0..<3 {
      group.spawn_bg(() => {
        cond.wait()
        woke.push(i)
      })
      @async.sleep(0)
      for _ in 0..<100 {
        let task = group.spawn(() => cond.wait())
        @async.sleep(0)
        task.cancel()
        task.wait() catch {
          @async.TaskCancelled => ()
          err => raise err
        }
      }
    }
    assert_true(cond.waiters.length() <= 67)
    for i in 0..<3 {
      cond.signal()
      @async.sleep(0)
      assert_eq(woke.length(), i + 1)
      assert_eq(woke[i], i)
    }
    cond.signal()
    assert_eq(cond.waiters.length(), 0)
  })
}

///|
async test "broadcast followed by cancellation preserves notification and reuse" {
  let cond = Cond()
  let woke : Array[Int] = []
  @async.with_task_group(group => {
    for round in 0..<3 {
      for _ in 0..<100 {
        let task = group.spawn(() => cond.wait())
        @async.sleep(0)
        task.cancel()
        task.wait() catch {
          @async.TaskCancelled => ()
          err => raise err
        }
      }
      let task = group.spawn(() => {
        cond.wait()
        woke.push(round)
      })
      @async.sleep(0)
      cond.broadcast()
      task.cancel()
      task.wait() catch {
        @async.TaskCancelled => ()
        err => raise err
      }
      assert_eq(woke.length(), round + 1)
      assert_eq(woke[round], round)
      assert_eq(cond.waiters.length(), 0)
    }
  })
}
