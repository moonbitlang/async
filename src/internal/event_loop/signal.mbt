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
  UnixSignalHandler
  ConsoleControlHandler
}

///|
#cfg(all(target="native", not(platform="windows")))
extern "C" fn start_signal_handler_ffi() -> Unit = "moonbitlang_async_start_signal_handler"

///|
#cfg(all(target="native", not(platform="windows")))
extern "C" fn terminate_signal_handler_ffi() -> Unit = "moonbitlang_async_terminate_signal_handler"

///|
#cfg(target="wasm")
#unsafe_skip_stub_check
fn start_signal_handler_ffi() -> Unit = "moonbitlang/async" "signal/start_signal_handler"

///|
#cfg(target="wasm")
#unsafe_skip_stub_check
fn terminate_signal_handler_ffi() -> Unit = "moonbitlang/async" "signal/terminate_signal_handler"

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
  if !global_signal_handler_initialized.val {
    set_global_cancellation_signals(all_signals)
  }
  start_signal_handler_ffi()
  UnixSignalHandler
}

///|
#cfg(all(target="native", not(platform="windows")))
fn EventLoop::terminate_signal_handler(
  evloop : EventLoop,
  handler : SignalHandler,
) -> Unit raise {
  guard! handler is UnixSignalHandler
  global_signal_handler_initialized.val = false
  terminate_signal_handler_ffi()
  if evloop.killed_by_signal is Some(signal) {
    raise KilledBySignal(signal)
  }
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
  guard! handler is ConsoleControlHandler
  global_signal_handler_initialized.val = false
  evloop.terminate_signal_handler_windows()
}

///|
#cfg(target="wasm")
fn setup_signal_handler() -> SignalHandler raise {
  if platform is Windows {
    setup_signal_handler_windows()
    ConsoleControlHandler
  } else {
    if !global_signal_handler_initialized.val {
      set_global_cancellation_signals(all_signals)
    }
    start_signal_handler_ffi()
    UnixSignalHandler
  }
}

///|
#cfg(target="wasm")
fn EventLoop::terminate_signal_handler(
  evloop : EventLoop,
  signal_handler : SignalHandler,
) -> Unit raise {
  global_signal_handler_initialized.val = false
  match signal_handler {
    UnixSignalHandler => {
      terminate_signal_handler_ffi()
      if evloop.killed_by_signal is Some(signal) {
        raise KilledBySignal(signal)
      }
    }
    ConsoleControlHandler => evloop.terminate_signal_handler_windows()
  }
}

///|
#cfg(target="native")
pub extern "C" fn terminate_process_by_signal(sig : Int) -> Unit = "moonbitlang_async_terminate_process_by_signal"
