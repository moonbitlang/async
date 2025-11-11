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
#deprecated("use `async fn main` or `async test` instead")
pub fn with_event_loop(f : async (TaskGroup[Unit]) -> Unit) -> Unit raise {
  @event_loop.with_event_loop(() => with_task_group(f))
}

///|
/// `sleep` will wait for the given time (in milliseconds) before returning.
/// Other task can still run while current task is sleeping.
/// If current task is cancelled, `sleep` will return early with an error.
pub using @event_loop {sleep}

///|
/// Pause current task and give other tasks chance to execute.
/// When performing long running pure computation (i.e. no IO involved),
/// `pause` can be used to avoid starving other tasks.
pub using @coroutine {pause}

///|
pub suberror TimeoutError derive(Show)

///|
/// `with_timeout(timeout, f)` run the async function `f`.
///
/// - If `f` return `value` before `timeout`,
///   `with_timeout` will return `value` immediately.
///
/// - If `f` fail before `timeout`, `with_timeout` will fail immediately.
///
/// - If `f` is still running after `timeout` milliseconds,
///   `with_timeout` will fail with `TimeoutError`,
///   or the value of `error`, if explicitly specified.
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
/// `with_timeout_opt(timeout, f)` run the async function `f`.
///
/// - If `f` return `value` before `timeout`,
///   `with_timeout_opt` will return `Some(value)` immediately.
///
/// - If `f` fail before `timeout`, `with_timeout_opt` will fail immediately.
///
/// - If `f` is still running after `timeout` milliseconds,
/// ` with_timeout_opt` will return `None` immediately, and `f` will be cancelled.
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
pub using @coroutine {protect_from_cancel}

///|
/// Get current time, measured in milliseconds.
/// `now` uses the same clock as timers in `moonbitlang/async`.
///
/// `now` can be used to measure elapsed time, such as benchmarking,
/// but the meaning of the absolute time value returned by `now`
/// is undefined, and should not be depended on.
pub fn now() -> Int64 {
  @time.ms_since_epoch()
}

///|
pub using @aqueue {type Queue}

///|
pub using @semaphore {type Semaphore}

///|
pub type CondVar = @cond_var.Cond

///|
/// `RetryMethod` describes different retry strategies used by various APIs:
///
/// - `Immediate`: failed task will immediately be restarted.
///
/// - `FixedDelay(t)`,
///   failed task will be restarted after sleeping for `t` milliseconds
///
/// - `ExponentialDelay(initial~, factor~, maximum~)`:
///   failed task will be restarted with an exponentially growing delay.
///   The initial delay is `initial`, and after every failure,
///   the delay will be multiplied by `factor`, but will never exceed `maximum`.
pub(all) enum RetryMethod {
  Immediate
  FixedDelay(Int)
  ExponentialDelay(initial~ : Int, factor~ : Double, maximum~ : Int)
}

///|
/// `retry(strategy, f)` will keep retrying some async operation until success.
/// If `f` returns `value` normally, `retry` will immediately return `value`.
/// If `f` fails with error, `retry` will restart `f` again.
/// The restart strategy is determined by `strategy`,
/// see the `RetryMethod` type for more details.
///
/// If current task is cancelled, `retry` will be cancelled too.
///
/// By default, the number of retry attempt is unbounded.
/// However, if `max_retry` is set,
/// the number of retry attempts will not exceed the value of `max_retry`.
/// If retry attempts reaches limit, `retry` will raise the error from `f`'s last attempt.
///
/// If `fatal_error` is present, and `f` raises an error `err` such that
/// `fatal_error(err)` is `true`, `retry` will fail immediately with `err`.
#alias(retry, visibility="pub")
// the long name here is used to avoid name clash with
// labelled argument `retry` of `spawn_loop`.
async fn[X] moonbitlang_async_retry(
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
