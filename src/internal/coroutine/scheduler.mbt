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

/// The scheduler manages coroutine execution and maintains the global state
/// for the async runtime system.
priv struct Scheduler {
  /// Counter for generating unique coroutine IDs
  mut coro_id : Int
  /// The currently executing coroutine, if any
  mut curr_coro : Coroutine?
  /// Number of coroutines that are blocked waiting for external events
  mut blocking : Int
  /// Queue of coroutines that are ready to run
  run_later : @deque.Deque[Coroutine]
}

/// Global scheduler instance that manages all coroutine execution
let scheduler : Scheduler = {
  coro_id: 0,
  curr_coro: None,
  blocking: 0,
  run_later: @deque.new(),
}

/// Returns the currently executing coroutine.
/// Panics if called outside of a coroutine context.
pub fn current_coroutine() -> Coroutine {
  scheduler.curr_coro.unwrap()
}

/// Checks if there are any coroutines ready to run immediately.
/// Returns true if the scheduler has coroutines queued for execution.
pub fn has_immediately_ready_task() -> Bool {
  !scheduler.run_later.is_empty()
}

/// Checks if the scheduler has no more work to do.
/// Returns true if there are no ready coroutines and no blocked coroutines.
/// This indicates that all async work has completed.
pub fn no_more_work() -> Bool {
  scheduler.blocking == 0 && scheduler.run_later.is_empty()
}

/// Executes all ready coroutines in the scheduler queue.
/// This function runs each ready coroutine until it either completes,
/// suspends, or yields control. Coroutines that are cancelled will
/// receive the Cancelled error.
pub fn reschedule() -> Unit {
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
  }
}
