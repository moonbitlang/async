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
  mut coro_id : Int32
  mut curr_coro : Coroutine?
  run_later : @deque.Deque[Coroutine]
  all_coros : Set[Coroutine]
}

///|
// An intermediate type compiled to `void*` on C backend.
// Used to work around `-Wincompatible-pointer-types` from the C compiler.
priv type CoreScheduler

///|
#warnings("-alert_internal")
fn CoreScheduler::from_impl(
  scheduler : @runtime_internal.Scheduler,
) -> CoreScheduler = "%identity"

///|
fn from_core_scheduler(x : CoreScheduler) -> Scheduler = "%identity"

///|
// Here the cast is decomposed into two parts: core type -> void* -> our type.
// This works around `-Wincompatible-pointer-types` from the C compiler.
// This is hacky, but the whole runtime sharing mechanism is a big temporary hack,
// so we choose to live with it here.
#warnings("-alert_internal")
let scheduler : Scheduler = from_core_scheduler(
  CoreScheduler::from_impl(@runtime_internal.get_current_scheduler()),
)

///|
pub fn current_coroutine() -> Coroutine {
  scheduler.curr_coro.unwrap()
}

///|
pub fn has_immediately_ready_task() -> Bool {
  !scheduler.run_later.is_empty()
}

///|
/// Perform a new rousd of scheduling by running all ready coroutines.
/// While running these coroutines, new coroutines may get waken or spawned,
/// these new coroutines will *not* get executed in this run of `reschedule`.
/// This give the event loop a chance to check of completed IO operations
/// and prevent starvation, even when there is always immediately ready coroutine.
pub fn reschedule() -> Unit {
  let n = scheduler.run_later.length()
  for _ in 0..<n {
    guard scheduler.run_later.pop_front() is Some(coro) else { break }
    coro.ready = false
    guard coro.state is Suspend(cont) else {  }
    coro.state = Running
    let last_coro = scheduler.curr_coro
    scheduler.curr_coro = Some(coro)
    if coro.cancelled && !coro.shielded {
      cont(Cancelled)
    } else {
      cont(Continue)
    }
    scheduler.curr_coro = last_coro
  }
}

///|
pub fn all_coroutines() -> Set[Coroutine] {
  scheduler.all_coros
}
