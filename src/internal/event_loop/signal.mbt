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
extern "C" fn get_signal_by_index(index : Int32) -> Int32 = "moonbitlang_async_get_signal_by_index"

///|
#cfg(target="wasm")
#unsafe_skip_stub_check
fn get_signal_by_index(index : Int32) -> Int32 = "moonbitlang/async" "signal/get_signal_by_index"

///|
pub let all_signals : ReadOnlyArray[Int32] = ReadOnlyArray::makei(
  4, get_signal_by_index,
)

///|
#cfg(target="native")
#borrow(all_signals, signals)
extern "C" fn set_global_cancellation_signals_ffi(
  all_signals : ReadOnlyArray[Int32],
  all_signals_len : Int32,
  signals : ReadOnlyArray[Int32],
  signals_len : Int32,
) -> Unit = "moonbitlang_async_set_global_cancellation_signals"

///|
#cfg(target="wasm")
#unsafe_skip_stub_check
#borrow(all_signals, signals)
fn set_global_cancellation_signals_ffi(
  all_signals : ReadOnlyArray[Int32],
  all_signals_len : Int32,
  signals : ReadOnlyArray[Int32],
  signals_len : Int32,
) -> Unit = "moonbitlang/async" "signal/set_global_cancellation_signals"

///|
let global_signal_handler_initialized : Ref[Bool] = Ref(false)

///|
pub fn set_global_cancellation_signals(signals : ReadOnlyArray[Int32]) -> Unit {
  global_signal_handler_initialized.val = true
  set_global_cancellation_signals_ffi(
    all_signals,
    all_signals.length(),
    signals,
    signals.length(),
  )
}

///|
#cfg(target="native")
pub extern "C" fn terminate_process_by_signal(sig : Int32) -> Unit = "moonbitlang_async_terminate_process_by_signal"
