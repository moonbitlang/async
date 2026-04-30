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
#external
type Timer

///|
#cfg(target="js")
extern "js" fn set_timeout(duration : Int, f : () -> Unit) -> Timer =
  #| (duration, f) => setTimeout(f, duration)

///|
#cfg(target="wasm-gc")
fn set_timeout(duration : Int, f : () -> Unit) -> Timer = "moonbitlang_async_timer" "setTimeout"

///|
pub fn Timer::new(duration : Int, f : () -> Unit) -> Timer {
  set_timeout(duration, () => {
    f()
    reschedule()
  })
}

///|
#cfg(target="js")
pub extern "js" fn Timer::cancel(self : Timer) =
  #| (timer) => clearTimeout(timer)

///|
#cfg(target="wasm-gc")
fn clear_timeout(timer : Timer) = "moonbitlang_async_timer" "clearTimeout"

///|
#cfg(target="wasm-gc")
pub fn Timer::cancel(self : Timer) -> Unit {
  clear_timeout(self)
}
