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
fn get_signal_by_name(_name : Bytes) -> Int {
  // not implemented yet on Wasm
  -1
}

///|
pub let _SIGINT : Int = get_signal_by_name(b"SIGINT")

///|
pub let _SIGTERM : Int = get_signal_by_name(b"SIGTERM")

///|
pub let _SIGHUP : Int = get_signal_by_name(b"SIGHUP")

///|
pub let _SIGBREAK : Int = get_signal_by_name(b"SIGBREAK")

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
fn set_global_cancellation_signals_ffi(
  all_signals : ReadOnlyArray[Int],
  signals : ReadOnlyArray[Int],
) -> Unit {
  // not implemented yet on Wasm
  ignore(all_signals)
  ignore(signals)
}

///|
let global_signal_handler_initialized : Ref[Bool] = Ref(false)

///|
pub fn set_global_cancellation_signals(signals : ReadOnlyArray[Int]) -> Unit {
  global_signal_handler_initialized.val = true
  set_global_cancellation_signals_ffi(all_signals, signals)
}

///|
#cfg(all(target="native", not(platform="windows")))
fn setup_signal_handler() -> @coroutine.Coroutine {
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
#cfg(all(target="native", not(platform="windows")))
async fn EventLoop::terminate_signal_handler(
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
#cfg(platform="windows")
fn setup_signal_handler() -> Unit raise {
  if !global_signal_handler_initialized.val {
    set_global_cancellation_signals(all_signals)
  }
  if set_console_control_handler(1) is 0 {
    @os_error.check_errno("setup_signal_handler()")
  }
}

///|
#cfg(platform="windows")
fn EventLoop::terminate_signal_handler(
  evloop : EventLoop,
  _ : Unit,
) -> Unit raise {
  if set_console_control_handler(0) is 0 {
    @os_error.check_errno("terminate_signal_handler()")
  }
  if evloop.killed_by_signal is Some(signal) {
    raise KilledBySignal(signal)
  }
}

///|
#cfg(target="wasm")
fn setup_signal_handler() -> Unit {
  ()
}

///|
#cfg(target="wasm")
fn EventLoop::terminate_signal_handler(
  evloop : EventLoop,
  _ : Unit,
) -> Unit raise {
  if evloop.killed_by_signal is Some(signal) {
    raise KilledBySignal(signal)
  }
}
