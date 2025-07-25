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
priv struct Timer {
  timer_id : Int
  expire_time : Int64
  coro : Coroutine
}

///|
let timer_id : Ref[Int] = { val: 0 }

///|
fn Timer::new(duration : Int, coro : Coroutine) -> Timer {
  let expire_time = @time.ms_since_epoch() + duration.to_int64()
  timer_id.val += 1
  { timer_id: timer_id.val, expire_time, coro }
}

///|
impl Eq for Timer with op_equal(t1, t2) {
  t1.timer_id == t2.timer_id
}

///|
impl Compare for Timer with compare(t1, t2) {
  match t1.expire_time.compare(t2.expire_time) {
    0 => t1.timer_id.compare(t2.timer_id)
    o => o
  }
}

///|
priv struct Scheduler {
  mut coro_id : Int
  mut curr_coro : Coroutine?
  mut blocking : Int
  run_later : @deque.T[Coroutine]
  timers : @sorted_set.T[Timer]
}

///|
let scheduler : Scheduler = {
  coro_id: 0,
  curr_coro: None,
  blocking: 0,
  run_later: @deque.new(),
  timers: @sorted_set.new(),
}

///|
pub fn current_coroutine() -> Coroutine {
  scheduler.curr_coro.unwrap()
}

///|
pub fn next_expire_time() -> Int64? {
  if scheduler.timers.iter().head() is Some(timer) {
    Some(timer.expire_time)
  } else {
    None
  }
}

///|
pub fn no_more_work() -> Bool {
  scheduler.blocking == 0 &&
  scheduler.run_later.is_empty() &&
  scheduler.timers.is_empty()
}

///|
fn Scheduler::flush_timer(scheduler : Scheduler) -> Unit {
  while scheduler.timers.iter().head() is Some(timer) &&
        timer.expire_time <= @time.ms_since_epoch() {
    scheduler.timers.remove(timer)
    timer.coro.wake()
  }
}

///|
pub fn reschedule() -> Unit {
  scheduler.flush_timer()
  while scheduler.run_later.pop_front() is Some(coro) {
    coro.ready = false
    guard coro.state is Suspend(ok_cont~, err_cont~) else {  }
    coro.state = Running
    let last_coro = scheduler.curr_coro
    scheduler.curr_coro = Some(coro)
    if coro.cancelled && not(coro.shielded) {
      err_cont(Cancelled)
    } else {
      ok_cont(())
    }
    scheduler.curr_coro = last_coro
    scheduler.flush_timer()
  }
}
