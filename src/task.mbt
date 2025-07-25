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
/// `Task[X]` represents a running task with result type `X`,
/// it can be used to wait and retrieve the result value of the task.
struct Task[X] {
  value : Ref[X?]
  coro : @coroutine.Coroutine
}

///|
/// Wait for a task and retrieve its result value.
/// If the task fails, `wait` will also fail with the same error.
///
/// If the current task is cancelled, `wait` return immediately with error.
pub async fn[X] Task::wait(self : Task[X]) -> X raise {
  self.coro.wait()
  self.value.val.unwrap()
}

///|
/// Cancel a task. Subsequent attempt to wait for the task will receive error.
/// Note that if the task is *not* spawned with `allow_failure=true`,
/// the whole task group will fail too.
pub fn[X] Task::cancel(self : Task[X]) -> Unit {
  self.coro.cancel()
}
