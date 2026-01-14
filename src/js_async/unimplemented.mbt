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
let _ignore_unused_import : Unit = {
  ignore(@coroutine.spawn)
  ignore(@event_loop.sleep)
}

///|
/// A JavaScript promise that resolves to a value of type `X`
#external
#internal(unimplemented, "unimplemented in native backend")
pub type Promise[X]

///|
/// A JavaScript exception wrapped in MoonBit error
#internal(unimplemented, "unimplemented in native backend")
suberror JsError {
  JsError(Unit)
}

///|
#internal(unimplemented, "unimplemented in native backend")
pub impl Show for JsError with output(self, _logger) {
  let JsError(x) = self
  let _ = JsError(x)
  abort("unimplemented in native backend")
}

///|
/// A JavaScript `AbortController` used to cancel promises
#external
#internal(unimplemented, "unimplemented in native backend")
pub type AbortController

///|
/// A JavaScript `AbortSignal` used to cancel promises
#external
#internal(unimplemented, "unimplemented in native backend")
pub type AbortSignal

///|
/// Create a new abort controller
#internal(unimplemented, "unimplemented in native backend")
pub fn AbortController::new() -> AbortController {
  abort("unimplemented in native backend")
}

///|
/// Get the abort signal of an abort controller.
/// The abort signal will be triggered when `.abort()` is called on the controller.
#internal(unimplemented, "unimplemented in native backend")
pub fn AbortController::signal(self : Self) -> AbortSignal {
  ignore(self)
  abort("unimplemented in native backend")
}

///|
/// Abort the abort controller and activate its abort signal.
/// All promises tied to the signal will be cancelled.
#internal(unimplemented, "unimplemented in native backend")
pub fn AbortController::abort(self : Self) -> Unit {
  ignore(self)
  abort("unimplemented in native backend")
}

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
#internal(unimplemented, "unimplemented in native backend")
#warnings("-unused_async")
pub async fn[X] Promise::wait(
  promise : Promise[X],
  abort_controller? : AbortController,
) -> X {
  ignore(promise)
  ignore(abort_controller)
  abort("unimplemented in native backend")
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
#internal(unimplemented, "unimplemented in native backend")
#warnings("-unused_async")
pub async fn[X] run_promise(f : (AbortSignal) -> Promise[X]) -> X {
  ignore(f)
  abort("unimplemented in native backend")
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
#internal(unimplemented, "unimplemented in native backend")
#warnings("-unused_async")
pub fn[X] Promise::from_async(
  f : async () -> X,
  abort_signal? : AbortSignal,
) -> Promise[X] {
  ignore(f)
  ignore(abort_signal)
  abort("unimplemented in native backend")
}
