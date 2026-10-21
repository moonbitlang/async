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
// Package imports are shared across target-specific files. Native event-loop
// files need `@c_buffer`, while the wasm target does not otherwise touch it.
let _target_specific_imports : Unit = {
  ignore(@c_buffer.Buffer::is_null)
  ignore((_ : &@external_loop_integration.ExternalEventLoop) => ())
}

///|
priv enum PlatformEventLoopExtra {
  Unix(UnixEventLoopExtra)
  Windows(WindowsEventLoopExtra)
}

///|
async fn PlatformEventLoopExtra::wait_pid(
  self : Self,
  evloop : EventLoop,
  pid : Int32,
) -> Unit {
  match self {
    Unix(extra) => extra.wait_pid(evloop, pid)
    Windows(_) => panic()
  }
}
