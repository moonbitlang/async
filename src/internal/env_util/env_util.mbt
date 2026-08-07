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
extern "C" fn get_pid() -> UInt = "moonbitlang_async_getpid"

///|
#cfg(target="wasm")
#unsafe_skip_stub_check
fn get_pid() -> UInt = "moonbitlang/async" "env_util/getpid"

///|
#cfg(any(target="native", target="wasm"))
pub let current_process : UInt = get_pid()

///|
#cfg(target="native")
#borrow(msg)
pub extern "C" fn eprintln(msg : String) -> Unit = "moonbitlang_async_eprintln"

///|
#cfg(not(target="native"))
pub fn eprintln(msg : String) -> Unit {
  println(msg)
}
