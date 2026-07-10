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
#cfg(target="native")
#borrow(name)
extern "C" fn get_signal_by_name(name : Bytes) -> Int = "moonbitlang_async_get_signal_by_name"

///|
#cfg(target="wasm")
#unsafe_skip_stub_check
fn get_signal_by_index(index : Int) -> Int = "moonbitlang/async" "signal/get_signal_by_index"

///|
#cfg(target="wasm")
let sigint_index : Int = 0

///|
#cfg(target="wasm")
let sigterm_index : Int = 1

///|
#cfg(target="wasm")
let sighup_index : Int = 2

///|
#cfg(target="wasm")
let sigbreak_index : Int = 3

///|
#cfg(target="native")
pub let _SIGINT : Int = get_signal_by_name(b"SIGINT")

///|
#cfg(target="wasm")
pub let _SIGINT : Int = get_signal_by_index(sigint_index)

///|
#cfg(target="native")
pub let _SIGTERM : Int = get_signal_by_name(b"SIGTERM")

///|
#cfg(target="wasm")
pub let _SIGTERM : Int = get_signal_by_index(sigterm_index)

///|
#cfg(target="native")
pub let _SIGHUP : Int = get_signal_by_name(b"SIGHUP")

///|
#cfg(target="wasm")
pub let _SIGHUP : Int = get_signal_by_index(sighup_index)

///|
#cfg(target="native")
pub let _SIGBREAK : Int = get_signal_by_name(b"SIGBREAK")

///|
#cfg(target="wasm")
pub let _SIGBREAK : Int = get_signal_by_index(sigbreak_index)

///|
let all_signals : ReadOnlyArray[Int] = [_SIGINT, _SIGTERM, _SIGHUP, _SIGBREAK]

///|
pub suberror KilledBySignal {
  KilledBySignal(Int)
}

///|
#cfg(target="native")
#borrow(all_signals, signals)
extern "C" fn set_global_cancellation_signals_ffi(
  all_signals : ReadOnlyArray[Int],
  signals : ReadOnlyArray[Int],
) -> Unit = "moonbitlang_async_set_global_cancellation_signals"

///|
#cfg(target="wasm")
#unsafe_skip_stub_check
#borrow(all_signals, signals)
fn set_global_cancellation_signals_ffi(
  all_signals : ReadOnlyArray[Int],
  all_signals_len : Int,
  signals : ReadOnlyArray[Int],
  signals_len : Int,
) -> Unit = "moonbitlang/async" "signal/set_global_cancellation_signals"

///|
let global_signal_handler_initialized : Ref[Bool] = Ref(false)

///|
#cfg(target="native")
pub fn set_global_cancellation_signals(signals : ReadOnlyArray[Int]) -> Unit {
  global_signal_handler_initialized.val = true
  set_global_cancellation_signals_ffi(all_signals, signals)
}

///|
#cfg(target="wasm")
pub fn set_global_cancellation_signals(signals : ReadOnlyArray[Int]) -> Unit {
  global_signal_handler_initialized.val = true
  set_global_cancellation_signals_ffi(
    all_signals,
    all_signals.length(),
    signals,
    signals.length(),
  )
}

///|
#cfg(not(platform="windows"))
fn setup_sigwait_signal_handler() -> @coroutine.Coroutine {
  if !global_signal_handler_initialized.val {
    set_global_cancellation_signals(all_signals)
  }
  @coroutine.spawn() <| () => {
    let context = "sigwait thread"
    fn cancel(job_id) raise {
      guard curr_loop.val is Some(evloop)
      evloop.cancel_job_in_worker(job_id, context~)
    }
    let job = Job::sigwait(all_signals)
    defer job.free()
    ignore <| perform_job_in_worker(job, context~, cancel~)
  }
}

///|
#cfg(not(platform="windows"))
async fn EventLoop::terminate_sigwait_signal_handler(
  evloop : EventLoop,
  sigwait_task : @coroutine.Coroutine,
) -> Unit {
  sigwait_task.cancel()
  @coroutine.protect_from_cancel(() => sigwait_task.wait()) catch {
    @coroutine.Cancelled => ()
    err => raise err
  }
  if evloop.killed_by_signal is Some(signal) {
    raise KilledBySignal(signal)
  }
}

///|
#cfg(platform="windows")
extern "C" fn set_console_control_handler(add : Int) -> Int = "moonbitlang_async_set_console_control_handler"

///|
#cfg(target="wasm")
#unsafe_skip_stub_check
fn set_console_control_handler(add : Int) -> Int = "moonbitlang/async" "signal/set_console_control_handler"

///|
#cfg(any(target="wasm", platform="windows"))
fn setup_console_control_signal_handler() -> Unit raise {
  if !global_signal_handler_initialized.val {
    set_global_cancellation_signals(all_signals)
  }
  if set_console_control_handler(1) is 0 {
    @os_error.check_errno("setup_signal_handler()")
  }
}

///|
#cfg(any(target="wasm", platform="windows"))
fn EventLoop::terminate_console_control_signal_handler(
  evloop : EventLoop,
) -> Unit raise {
  if set_console_control_handler(0) is 0 {
    @os_error.check_errno("terminate_signal_handler()")
  }
  if evloop.killed_by_signal is Some(signal) {
    raise KilledBySignal(signal)
  }
}

///|
#cfg(all(target="native", not(platform="windows")))
fn setup_signal_handler() -> @coroutine.Coroutine {
  setup_sigwait_signal_handler()
}

///|
#cfg(all(target="native", not(platform="windows")))
async fn EventLoop::terminate_signal_handler(
  evloop : EventLoop,
  sigwait_task : @coroutine.Coroutine,
) -> Unit {
  evloop.terminate_sigwait_signal_handler(sigwait_task)
}

///|
#cfg(platform="windows")
fn setup_signal_handler() -> Unit raise {
  setup_console_control_signal_handler()
}

///|
#cfg(platform="windows")
fn EventLoop::terminate_signal_handler(
  evloop : EventLoop,
  _ : Unit,
) -> Unit raise {
  evloop.terminate_console_control_signal_handler()
}

///|
#cfg(target="wasm")
priv enum SignalHandler {
  Sigwait(@coroutine.Coroutine)
  ConsoleControl
}

///|
#cfg(target="wasm")
fn setup_signal_handler() -> SignalHandler raise {
  if platform is Windows {
    setup_console_control_signal_handler()
    ConsoleControl
  } else {
    Sigwait(setup_sigwait_signal_handler())
  }
}

///|
#cfg(target="wasm")
async fn EventLoop::terminate_signal_handler(
  evloop : EventLoop,
  signal_handler : SignalHandler,
) -> Unit {
  match signal_handler {
    Sigwait(sigwait_task) =>
      evloop.terminate_sigwait_signal_handler(sigwait_task)
    ConsoleControl => evloop.terminate_console_control_signal_handler()
  }
}
