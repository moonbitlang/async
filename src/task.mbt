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
/// `Task[X]` represents a running asynchronous task with result type `X`.
/// 
/// Tasks are created by spawning functions using `TaskGroup::spawn()` and provide
/// a handle to monitor, wait for, and potentially cancel the execution.
/// 
/// # Example
/// ```moonbit
/// async fn example() {
///   @async.with_task_group(fn(group) {
///     let task = group.spawn(fn() {
///       @async.sleep(100)
///       42
///     })
///     
///     let result = task.wait()  // blocks until task completes
///     inspect(result, content="42")
///   })
/// }
/// ```
struct Task[X] {
  value : Ref[X?]
  coro : @coroutine.Coroutine
}

///|
/// Wait for a task to complete and retrieve its result value.
/// 
/// This function blocks the current task until the target task finishes execution.
/// If the target task completes successfully, its return value is returned.
/// If the target task fails with an error, `wait` will propagate that error.
/// 
/// If the current task is cancelled while waiting, `wait` returns immediately with a cancellation error.
/// 
/// # Parameters
/// - `self`: The task to wait for
/// 
/// # Returns
/// The result value of the completed task
/// 
/// # Raises
/// - The same error that caused the task to fail
/// - Cancellation error if the current task is cancelled
/// 
/// # Example
/// ```moonbit
/// async fn example() {
///   @async.with_task_group(fn(group) {
///     let task = group.spawn(fn() {
///       @async.sleep(50)
///       "Hello, World!"
///     })
///     
///     let message = task.wait()
///     inspect(message, content="Hello, World!")
///   })
/// }
/// ```
pub async fn[X] Task::wait(self : Task[X]) -> X {
  self.coro.wait()
  self.value.val.unwrap()
}

///|
/// Try to obtain the result of a task without blocking.
/// 
/// This is a non-blocking operation that immediately returns the task's status:
/// - If the task has completed successfully, returns `Some(result)`
/// - If the task is still running, returns `None`
/// - If the task has failed, raises the error immediately
/// 
/// This function is synchronous and never blocks, making it suitable for polling
/// the task status in performance-critical scenarios.
/// 
/// # Parameters
/// - `self`: The task to check
/// 
/// # Returns
/// - `Some(X)` if the task completed successfully
/// - `None` if the task is still running
/// 
/// # Raises
/// - The same error that caused the task to fail, if it has failed
/// 
/// # Example
/// ```moonbit
/// async fn example() {
///   @async.with_task_group(fn(group) {
///     let task = group.spawn(fn() {
///       @async.sleep(100)
///       "Done"
///     })
///     
///     // Check immediately - should be None (still running)
///     inspect(task.try_wait(), content="None")
///     
///     // Wait for completion then check again
///     @async.sleep(150)
///     inspect(task.try_wait(), content="Some("Done")")
///   })
/// }
/// ```
pub fn[X] Task::try_wait(self : Task[X]) -> X? raise {
  self.coro.check_error()
  self.value.val
}

///|
/// Cancel a running task, causing it to terminate with a cancellation error.
/// 
/// Once cancelled, the task will stop execution as soon as possible and any
/// subsequent calls to `wait()` or `try_wait()` will receive a cancellation error.
/// 
/// **Important**: If the task was not spawned with `allow_failure=true`, 
/// cancelling it will cause the entire task group to fail and all other 
/// tasks in the group will also be cancelled.
/// 
/// # Parameters
/// - `self`: The task to cancel
/// 
/// # Example
/// ```moonbit
/// async fn example() {
///   @async.with_task_group(fn(group) {
///     let task = group.spawn(allow_failure=true, fn() {
///       @async.sleep(1000)  // Long running task
///       "This won't complete"
///     })
///     
///     @async.sleep(50)  // Let task start
///     task.cancel()     // Cancel the task
///     
///     try {
///       task.wait()
///     } catch {
///       @coroutine.Cancelled => println("Task was cancelled as expected")
///     }
///   })
/// }
/// ```
pub fn[X] Task::cancel(self : Task[X]) -> Unit {
  self.coro.cancel()
}
