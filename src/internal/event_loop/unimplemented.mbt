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
#coverage.skip
let _ignore_unused_import : Unit = {
  ignore(@c_buffer.unimplemented)
  ignore(@fd_util.unimplemented)
  ignore(@os_string.unimplemented)
  ignore(@os_error.unimplemented)
  ignore(@time.ms_since_epoch)
  ignore(@coroutine.is_being_cancelled)
}

///|
type Timer

///|
pub fn Timer::new(duration : Int, callback : () -> Unit) -> Timer {
  ignore(duration)
  ignore(callback)
  abort("`Timer::new()` is unimplemented on WASM backend")
}

///|
pub fn Timer::cancel(timer : Timer) -> Unit {
  ignore(timer)
  abort("`Timer::cancel()` is unimplemented on WASM backend")
}

///|
/// WASM stub for the scheduler-only `reschedule` entry point. Drains
/// immediately-ready coroutines (including any wake-ups produced by
/// running coroutines themselves) and then returns. Gating on
/// `has_immediately_ready_task` rather than `no_more_work` ensures
/// blocked coroutines (`blocking > 0`, e.g. suspended on an external
/// host callback) do NOT cause this function to tight-spin: when there
/// is nothing ready to run we exit and yield back to the host, which
/// can re-enter via `run_async_main` once new work is available.
pub fn reschedule() -> Unit {
  while @coroutine.has_immediately_ready_task() {
    @coroutine.reschedule()
  }
}
