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
/// Create a fresh event loop and run a async program inside the loop.
/// A new task group will be created for convenience,
/// that is, `with_event_loop(f)` will run `with_task_group(f)` using the event loop.
///
/// There can only one event loop running for every program,
/// calling `with_event_loop` inside another event loop is invalid,
/// and will result in immediate failure.
pub fn with_event_loop(f : async (TaskGroup[Unit]) -> Unit raise) -> Unit raise {
  @event_loop.with_event_loop(() => with_task_group(f))
}

///|
/// `sleep` will wait for the given time (in milliseconds) before returning.
/// Other task can still run while current task is sleeping.
/// If current task is cancelled, `sleep` will return early with an error.
pub fnalias @coroutine.sleep

///|
/// Pause current task and give other tasks chance to execute.
/// When performing long running pure computation (i.e. no IO involved),
/// `pause` can be used to avoid starving other tasks.
pub fnalias @coroutine.pause

///|
/// `with_timeout(timeout, f)` run the async function `f`.
/// If `f` return or fail before `timeout`,
/// `with_timeout` return immediately with the same result.
/// If `f` is still running after `timeout` milliseconds,
/// `with_timeout` will also return immediately, and `f` will be cancelled.
pub async fn with_timeout(time : Int, f : async () -> Unit raise) -> Unit raise {
  with_task_group(fn(group) {
    group.spawn_bg(no_wait=true, fn() {
      sleep(time)
      group.return_immediately(())
    })
    f()
  })
}

///|
/// `protect_from_cancel(f)` executes `f` and protect `f` from cancellation.
/// If current task is cancelled while running `protect_from_cancel(f)`,
/// `f` will be protected from the cancellation and still run to finish,
/// and the cancellation will be delayed until `f` returns.
/// Things waiting for current task, such as the task group,
/// will also wait until `f` finish.
///
/// This function should be use with extra care and only when absolutely necessary,
/// because it will break other abstraction such as `with_timeout`.
/// A common scenario is avoiding corrupted state due to partial write to file etc.
pub fnalias @coroutine.protect_from_cancel
