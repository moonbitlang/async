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
extern "C" fn get_signal_by_index(index : Int) -> Int = "moonbitlang_async_get_signal_by_index"

///|
#cfg(target="wasm")
#unsafe_skip_stub_check
fn get_signal_by_index(index : Int) -> Int = "moonbitlang/async" "signal/get_signal_by_index"

///|
pub let all_signals : ReadOnlyArray[Int] = ReadOnlyArray::makei(
  4, get_signal_by_index,
)

///|
pub suberror KilledBySignal {
  KilledBySignal(Int)
}

///|
#cfg(target="native")
#borrow(all_signals, signals)
extern "C" fn set_global_cancellation_signals_ffi(
  all_signals : ReadOnlyArray[Int],
  all_signals_len : Int,
  signals : ReadOnlyArray[Int],
  signals_len : Int,
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
#warnings("-unused_constructor")
priv enum SignalHandler {
  SigwaitHandler(@coroutine.Coroutine)
  ConsoleControlHandler
}

///|
#cfg(not(platform="windows"))
fn setup_signal_handler_unix() -> @coroutine.Coroutine {
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
async fn EventLoop::terminate_signal_handler_unix(
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
fn setup_signal_handler_windows() -> Unit raise {
  if !global_signal_handler_initialized.val {
    set_global_cancellation_signals(all_signals)
  }
  if set_console_control_handler(1) is 0 {
    @os_error.check_errno("setup_signal_handler()")
  }
}

///|
#cfg(any(target="wasm", platform="windows"))
fn EventLoop::terminate_signal_handler_windows(
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
fn setup_signal_handler() -> SignalHandler {
  SigwaitHandler(setup_signal_handler_unix())
}

///|
#cfg(all(target="native", not(platform="windows")))
async fn EventLoop::terminate_signal_handler(
  evloop : EventLoop,
  handler : SignalHandler,
) -> Unit {
  guard handler is SigwaitHandler(sigwait_task)
  evloop.terminate_signal_handler_unix(sigwait_task)
}

///|
#cfg(platform="windows")
fn setup_signal_handler() -> SignalHandler raise {
  setup_signal_handler_windows()
  ConsoleControlHandler
}

///|
#cfg(platform="windows")
fn EventLoop::terminate_signal_handler(
  evloop : EventLoop,
  handler : SignalHandler,
) -> Unit raise {
  guard handler is ConsoleControlHandler
  evloop.terminate_signal_handler_windows()
}

///|
#cfg(target="wasm")
fn setup_signal_handler() -> SignalHandler raise {
  if platform is Windows {
    setup_signal_handler_windows()
    ConsoleControlHandler
  } else {
    SigwaitHandler(setup_signal_handler_unix())
  }
}

///|
#cfg(target="wasm")
async fn EventLoop::terminate_signal_handler(
  evloop : EventLoop,
  signal_handler : SignalHandler,
) -> Unit {
  match signal_handler {
    SigwaitHandler(sigwait_task) =>
      evloop.terminate_signal_handler_unix(sigwait_task)
    ConsoleControlHandler => evloop.terminate_signal_handler_windows()
  }
}
