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
/// 
/// **Deprecated**: Use `async fn main` or `async test` instead.
#deprecated("use `async fn main` or `async test` instead")
pub fn with_event_loop(f : async (TaskGroup[Unit]) -> Unit) -> Unit raise {
  @event_loop.with_event_loop(() => with_task_group(f))
}

///|
/// Suspend the current task for the specified duration in milliseconds.
/// 
/// While the current task is sleeping, other tasks in the same task group 
/// or event loop can continue executing. This enables cooperative multitasking.
/// 
/// If the current task is cancelled while sleeping, this function will 
/// return early with a cancellation error.
/// 
/// # Parameters
/// - `ms`: Duration to sleep in milliseconds
/// 
/// # Raises
/// - Cancellation error if the current task is cancelled
/// 
/// # Example
/// ```moonbit
/// async fn example_sleep() {
///   let start = @async.now()
///   @async.sleep(100)
///   let elapsed = @async.now() - start
///   inspect(elapsed >= 100, content="true")
/// }
/// ```
pub fnalias @event_loop.sleep

///|
/// Voluntarily yield control to allow other tasks to execute.
/// 
/// This function is useful during long-running computations that don't 
/// involve I/O operations, as it prevents the current task from monopolizing 
/// the execution thread and starving other tasks.
/// 
/// # Example
/// ```moonbit
/// async fn example_pause() {
///   @async.with_task_group(fn(group) {
///     let mut counter = 0
///     
///     group.spawn_bg(fn() {
///       for i = 0; i < 1000; i = i + 1 {
///         counter += 1
///         if i % 100 == 0 {
///           @async.pause()  // Allow other tasks to run
///         }
///       }
///     })
///     
///     @async.sleep(50)  // Let the counter task run
///     inspect(counter > 0, content="true")
///   })
/// }
/// ```
pub fnalias @coroutine.pause

///|
/// Error raised when an operation times out.
/// 
/// This error is used by timeout-related functions such as `with_timeout`
/// and can be customized by providing an alternative error value.
pub suberror TimeoutError derive(Show)

///|
/// Execute an async function with a timeout.
/// 
/// This function runs the provided async function `f` and ensures it completes
/// within the specified time limit. If the function completes successfully 
/// before the timeout, its result is returned. If it fails before the timeout,
/// the error is propagated immediately. If the timeout is reached while the 
/// function is still running, a timeout error is raised.
/// 
/// # Parameters
/// - `time`: Timeout duration in milliseconds
/// - `f`: The async function to execute
/// - `error`: Optional custom error to raise on timeout (defaults to `TimeoutError`)
/// 
/// # Returns
/// The result of the async function if it completes within the timeout
/// 
/// # Raises
/// - The timeout error (or custom error) if the operation times out
/// - Any error raised by the async function `f`
/// 
/// # Example
/// ```moonbit
/// async fn example_timeout() {
///   // This will complete successfully
///   let result = @async.with_timeout(200, fn() {
///     @async.sleep(100)
///     "Success!"
///   })
///   inspect(result, content="Success!")
///   
///   // This will timeout
///   try {
///     @async.with_timeout(100, fn() {
///       @async.sleep(200)
///       "Won't complete"
///     })
///   } catch {
///     @async.TimeoutError => ()
///   }
/// }
/// ```
pub async fn[X] with_timeout(
  time : Int,
  f : async () -> X,
  error? : Error = TimeoutError,
) -> X {
  with_task_group(fn(group) {
    group.spawn_bg(no_wait=true, fn() {
      sleep(time)
      raise error
    })
    f()
  })
}

///|
/// Execute an async function with a timeout, returning `None` on timeout.
/// 
/// This function is similar to `with_timeout`, but instead of raising an error
/// when the timeout is reached, it returns `None` and cancels the running function.
/// This provides a more graceful way to handle timeouts when you want to 
/// continue execution rather than propagate an error.
/// 
/// # Parameters
/// - `time`: Timeout duration in milliseconds
/// - `f`: The async function to execute
/// 
/// # Returns
/// - `Some(result)` if the function completes within the timeout
/// - `None` if the timeout is reached
/// 
/// # Raises
/// - Any error raised by the async function `f` (before timeout)
/// 
/// # Example
/// ```moonbit
/// async fn example_timeout_opt() {
///   // This will complete successfully
///   let result1 = @async.with_timeout_opt(200, fn() {
///     @async.sleep(100)
///     "Success!"
///   })
///   inspect(result1, content="Some("Success!")")
///   
///   // This will timeout and return None
///   let result2 = @async.with_timeout_opt(100, fn() {
///     @async.sleep(200)
///     "Won't complete"
///   })
///   inspect(result2, content="None")
/// }
/// ```
pub async fn[X] with_timeout_opt(time : Int, f : async () -> X) -> X? {
  with_task_group(fn(group) {
    group.spawn_bg(no_wait=true, fn() {
      sleep(time)
      group.return_immediately(None)
    })
    Some(f())
  })
}

///|
/// Execute a function while protecting it from cancellation.
/// 
/// This function runs the provided function `f` and ensures that even if the 
/// current task is cancelled, `f` will continue to run until completion. 
/// The cancellation will be delayed until after `f` returns.
/// 
/// **Warning**: Use this function with extreme caution and only when absolutely 
/// necessary (e.g., critical cleanup operations, atomic file writes). 
/// Overusing this function can break higher-level abstractions like timeouts 
/// and proper cancellation handling.
/// 
/// # Parameters
/// - `f`: The function to protect from cancellation
/// 
/// # Returns
/// The result of the protected function
/// 
/// # Example
/// ```moonbit
/// async fn example_protect_cancel() {
///   @async.with_task_group(fn(group) {
///     let task = group.spawn(allow_failure=true, fn() {
///       try {
///         @async.with_timeout(50, fn() {
///           @async.protect_from_cancel(fn() {
///             @async.sleep(100)  // This will complete despite timeout
///             "Protected operation completed"
///           })
///         })
///       } catch {
///         @async.TimeoutError => "Timeout occurred after protection"
///       }
///     })
///     
///     let result = task.wait()
///     inspect(result, content="Protected operation completed")
///   })
/// }
/// ```
pub fnalias @coroutine.protect_from_cancel

///|
/// Get the current timestamp in milliseconds.
/// 
/// This function returns the current time measured in milliseconds since an 
/// unspecified epoch. The absolute value has no defined meaning and should 
/// not be relied upon. However, it's suitable for measuring elapsed time 
/// and benchmarking operations.
/// 
/// The timestamp uses the same clock as other timing functions in the async library.
/// 
/// # Returns
/// Current timestamp in milliseconds
/// 
/// # Example
/// ```moonbit
/// async fn example_now() {
///   let start = @async.now()
///   @async.sleep(100)
///   let end = @async.now()
///   let elapsed = end - start
///   inspect(elapsed >= 100, content="true")
/// }
/// ```
pub fnalias @time.ms_since_epoch as now

///|
/// Type alias for async-aware queue from the `@aqueue` module.
/// 
/// This queue provides thread-safe, asynchronous operations for producer-consumer 
/// patterns. Operations like `put` and `take` can block until space/items are available.
pub typealias @aqueue.Queue

///|
/// Type alias for async-aware semaphore from the `@semaphore` module.
/// 
/// Semaphores are used to control access to shared resources by limiting 
/// the number of concurrent operations that can proceed.
pub typealias @semaphore.Semaphore

///|
/// Defines different strategies for retrying failed operations.
/// 
/// The retry method determines how long to wait between retry attempts:
/// 
/// - `Immediate`: Retry immediately without any delay
/// - `FixedDelay(ms)`: Wait for a fixed number of milliseconds between retries
/// - `ExponentialDelay(initial, factor, maximum)`: Start with an initial delay 
///   and multiply by the factor after each failure, but never exceed the maximum
/// 
/// # Example
/// ```moonbit
/// fn example_retry_methods() {
///   // Immediate retry - no delay between attempts
///   let strategy1 = @async.RetryMethod::Immediate
///   
///   // Fixed 100ms delay between retries
///   let strategy2 = @async.RetryMethod::FixedDelay(100)
///   
///   // Exponential backoff: 10ms, 20ms, 40ms, 80ms, but max 500ms
///   let strategy3 = @async.RetryMethod::ExponentialDelay(
///     initial=10, factor=2.0, maximum=500
///   )
/// }
/// ```
pub(all) enum RetryMethod {
  Immediate
  FixedDelay(Int)
  ExponentialDelay(initial~ : Int, factor~ : Double, maximum~ : Int)
}

///|
/// Retry an async operation until it succeeds or reaches the retry limit.
/// 
/// This function will repeatedly execute the provided async function `f` until 
/// it returns successfully. The retry behavior is controlled by the strategy 
/// parameter, which determines the delay between attempts.
/// 
/// # Parameters
/// - `strategy`: The retry strategy to use (see `RetryMethod`)
/// - `max_retry`: Optional maximum number of retry attempts
/// - `fatal_error`: Optional predicate to identify non-retryable errors
/// - `f`: The async function to retry
/// 
/// # Returns
/// The result of the async function when it succeeds
/// 
/// # Raises
/// - The last error from `f` if retry limit is reached
/// - Fatal errors immediately (if `fatal_error` predicate returns true)
/// - Cancellation errors if the current task is cancelled
/// 
/// # Example
/// ```moonbit
/// async fn example_retry() {
///   let mut attempts = 0
///   
///   let result = @async.retry(
///     @async.RetryMethod::FixedDelay(50),
///     max_retry=3,
///     fn() {
///       attempts += 1
///       if attempts < 3 {
///         raise @async.TimeoutError()  // Simulate failure
///       }
///       "Success on attempt " + attempts.to_string()
///     }
///   )
///   
///   inspect(result, content="Success on attempt 3")
///   inspect(attempts, content="3")
/// }
/// ```
pub async fn[X] retry(
  strategy : RetryMethod,
  max_retry? : Int,
  fatal_error? : (Error) -> Bool,
  f : async () -> X,
) -> X {
  match strategy {
    Immediate =>
      for i = 0; ; i = i + 1 {
        try f() catch {
          err if fatal_error is Some(f) && f(err) => raise err
          err if @coroutine.is_being_cancelled() => raise err
          err if max_retry is Some(max) && i >= max => raise err
          _ => ()
        } noraise {
          result => return result
        }
      }
    FixedDelay(t) =>
      for i = 0; ; i = i + 1 {
        try f() catch {
          err if fatal_error is Some(f) && f(err) => raise err
          err if @coroutine.is_being_cancelled() => raise err
          err if max_retry is Some(max) && i >= max => raise err
          _ => sleep(t)
        } noraise {
          result => return result
        }
      }
    ExponentialDelay(initial~, factor~, maximum~) =>
      for i = 0, timeout = initial; ; i = i + 1 {
        try f() catch {
          err if fatal_error is Some(f) && f(err) => raise err
          err if @coroutine.is_being_cancelled() => raise err
          err if max_retry is Some(max) && i >= max => raise err
          _ => {
            sleep(timeout)
            continue i + 1,
              @cmp.minimum(maximum, (timeout.to_double() * factor).to_int())
          }
        } noraise {
          result => return result
        }
      }
  }
}
