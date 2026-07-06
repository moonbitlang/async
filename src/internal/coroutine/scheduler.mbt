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
priv struct Scheduler {
  mut coro_id : Int
  mut curr_coro : Coroutine?
  run_later : @deque.Deque[Coroutine]
  all_coros : Set[Coroutine]
}

///|
let scheduler : Scheduler = {
  coro_id: 0,
  curr_coro: None,
  run_later: Deque([]),
  all_coros: Set([]),
}

///|
pub fn current_coroutine() -> Coroutine {
  scheduler.curr_coro.unwrap()
}

///|
pub fn has_immediately_ready_task() -> Bool {
  !scheduler.run_later.is_empty()
}

///|
#valtype
priv struct CoroDesc {
  loc : String
  suspend_loc : String
  time : UInt64
} derive(Debug)

///|
/// Perform a new rousd of scheduling by running all ready coroutines.
/// While running these coroutines, new coroutines may get waken or spawned,
/// these new coroutines will *not* get executed in this run of `reschedule`.
/// This give the event loop a chance to check of completed IO operations
/// and prevent starvation, even when there is always immediately ready coroutine.
pub fn reschedule() -> Unit {
  let n = scheduler.run_later.length()
  let run_coros = Array::new(capacity=n)
  let start = @env.now()
  for _ in 0..<n {
    guard scheduler.run_later.pop_front() is Some(coro) else { break }
    coro.ready = false
    guard coro.state is Suspend(ok_cont~, err_cont~, loc~) else {  }
    coro.state = Running
    let last_coro = scheduler.curr_coro
    scheduler.curr_coro = Some(coro)
    let coro_loc = coro.loc
    let start = @env.now()
    if coro.cancelled && !coro.shielded {
      err_cont(Cancelled)
    } else {
      ok_cont(())
    }
    let t = @env.now() - start
    run_coros.push({
      loc: coro_loc.to_string(),
      suspend_loc: loc.to_string(),
      time: t,
    })
    scheduler.curr_coro = last_coro
  }
  let slice = @env.now() - start
  if slice > 50 {
    println("Scheduler slice took \{slice}ms. Related coroutines:")
    debug(run_coros)
  }
}

///|
pub fn all_coroutines() -> Set[Coroutine] {
  scheduler.all_coros
}
