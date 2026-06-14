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
/// A JavaScript promise that resolves to a value of type `X`
#external
pub type Promise[X]

///|
#external
priv type JsValue

///|
fn[X] JsValue::make(v : X) -> JsValue = "%identity"

///|
fn[X] JsValue::cast(v : JsValue) -> X = "%identity"

///|
fn JsValue::abort_error() -> JsValue = "moonbitlang_async_js" "abort_error"

///|
fn JsValue::to_string(v : JsValue) -> String = "moonbitlang_async_js" "jsvalue_to_string"

///|
/// A JavaScript exception wrapped in MoonBit error
suberror JsError {
  JsError(JsValue)
}

///|
pub impl Show for JsError with output(self, logger) {
  let JsError(value) = self
  logger.write_string(value.to_string())
}

///|
/// A JavaScript `AbortController` used to cancel promises
#external
pub type AbortController

///|
/// A JavaScript `AbortSignal` used to cancel promises
#external
pub type AbortSignal

///|
/// Create a new abort controller
pub fn AbortController::new() -> AbortController = "moonbitlang_async_js" "new_abort_controller"

///|
/// Get the abort signal of an abort controller.
/// The abort signal will be triggered when `.abort()` is called on the controller.
pub fn AbortController::signal(self : Self) -> AbortSignal = "moonbitlang_async_js" "abort_controller_signal"

///|
/// Abort the abort controller and activate its abort signal.
/// All promises tied to the signal will be cancelled.
pub fn AbortController::abort(self : Self) = "moonbitlang_async_js" "abort_controller_abort"

///|
fn AbortSignal::on_abort(signal : AbortSignal, f : () -> Unit) -> Unit = "moonbitlang_async_js" "abort_signal_on_abort"

///|
fn JsValue::then(
  promise : JsValue,
  resolve : (JsValue) -> Unit,
  reject : (JsValue) -> Unit,
) = "moonbitlang_async_js" "promise_then"

///|
/// A deferred promise with exposed resolve/reject handles.
/// Used instead of `new Promise(executor)` because wasm-gc cannot
/// directly call JS functions received as parameters.
#external
priv type Deferred

///|
fn Deferred::new() -> Deferred = "moonbitlang_async_js" "create_deferred"

///|
fn Deferred::resolve(self : Deferred, value : JsValue) -> Unit = "moonbitlang_async_js" "resolve_deferred"

///|
fn Deferred::reject(self : Deferred, err : JsValue) -> Unit = "moonbitlang_async_js" "reject_deferred"

///|
fn Deferred::promise(self : Deferred) -> JsValue = "moonbitlang_async_js" "get_deferred_promise"

///|
/// Wait for a JavaScript promise to resolve and return the fulfilled value,
/// or raise an error if the promise is rejected.
///
/// If `abort_controller` is provided,
/// it should be an abort controller that controls the promise,
/// and `.abort()` will be called on the controller automatically when `wait` is cancelled,
/// cancelling the promise automatically.
///
/// If `abort_controller` is absent, `wait` is non-cancellable.
pub async fn[X] Promise::wait(
  promise : Promise[X],
  abort_controller? : AbortController,
) -> X {
  struct Waiter {
    mut coro : @coroutine.Coroutine?
    mut ret : X?
    mut err : Error?
  }
  let waiter = {
    coro: Some(@coroutine.current_coroutine()),
    ret: None,
    err: None,
  }
  fn resolve(value : JsValue) {
    waiter.ret = Some(value.cast())
    if waiter.coro is Some(coro) {
      coro.wake()
      @event_loop.reschedule()
    }
  }

  fn reject(err) {
    waiter.err = Some(JsError(err))
    if waiter.coro is Some(coro) {
      coro.wake()
      @event_loop.reschedule()
    }
  }

  JsValue::make(promise).then(resolve, reject)
  defer {
    waiter.coro = None
  }
  if abort_controller is Some(controller) {
    @coroutine.suspend() catch {
      err => {
        controller.abort()
        raise err
      }
    }
  } else {
    @coroutine.protect_from_cancel(@coroutine.suspend)
  }
  if waiter.err is Some(err) {
    raise err
  } else {
    waiter.ret.unwrap()
  }
}

///|
/// Convenient helper for calling async JavaScript code from MoonBit.
/// `run_promise(f)` create a fresh abort signal, passed it to `f`,
/// and wait for the promise that `f` returns.
/// If `f` resolve to a value, `run_promise` return that value.
/// If `f` is rejected with an error, `run_promise` raise that error.
/// If `run_promise` is cancelled, the abort signal passed to `f` is activated,
/// and the promise returned by `f` should be cancelled automatically.
///
/// `run_promise` should only be used for cancellable JavaScript code
/// (i.e. the promised returned by `f` should properly handle the passed-in abort signal).
/// For non-cancellable JavaScript code, use `Promise::wait()` directly.
pub async fn[X] run_promise(f : (AbortSignal) -> Promise[X]) -> X {
  let controller = AbortController::new()
  let promise = f(controller.signal())
  promise.wait(abort_controller=controller)
}

///|
/// Convert a MoonBit async function into a JavaScript promise.
/// `Promise::from_async(f)` returns a promise that:
///
/// - resolve to the result of `f` when `f` return
/// - reject with the error that `f` raise if `f` fail
///
/// If `abort_signal` is present,
/// `f` will be automatically cancelled when the signal is activated,
/// and the returned promise will reject with JavaScript `AbortError`.
///
/// The async function `f` will be run in a global context,
/// so there is no structured concurrency support for `Promise::from_async`,
/// and this function should only be used for exporting MoonBit code to JavaScript.
///
/// It is undefined whether `f` will actually start running immediately,
/// or start at the next JavaScript event loop.
pub fn[X] Promise::from_async(
  f : async () -> X,
  abort_signal? : AbortSignal,
) -> Promise[X] {
  let deferred = Deferred::new()
  let coro = @coroutine.spawn(() => {
    try f() catch {
      @coroutine.Cancelled if @coroutine.is_being_cancelled() =>
        deferred.reject(JsValue::abort_error())
      err => deferred.reject(JsValue::make(err.to_string()))
    } noraise {
      ret => deferred.resolve(JsValue::make(ret))
    }
  })
  if abort_signal is Some(signal) {
    signal.on_abort(() => coro.cancel())
  }
  @coroutine.reschedule()
  deferred.promise().cast()
}
