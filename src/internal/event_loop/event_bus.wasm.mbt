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
/// The wasm event bus follows the native event-loop shape. Rust owns the OS
/// poller behind this opaque handle; MoonBit owns scheduling and dispatch.
priv struct EventBus(UInt64)

///|
#unsafe_skip_stub_check
fn EventBus::try_register_ffi(
  self : EventBus,
  fd : @fd_util.Fd,
  read_only : Bool,
) -> Int32 = "moonbitlang/async" "event_bus/try_register"

///|
fn EventBus::register(
  self : EventBus,
  fd : @fd_util.Fd,
  read_only~ : Bool,
) -> Bool raise {
  let ret = self.try_register_ffi(fd, read_only)
  if ret < 0 {
    @os_error.check_errno("runtime internal: @event_loop.EventBus::register()")
  }
  ret > 0
}

///|
#unsafe_skip_stub_check
fn EventBus::register_pid_ffi(self : EventBus, pid : Int32) -> Int32 = "moonbitlang/async" "event_bus/register_pid"

///|
/// Return `true` if the PID is successfully registered.
/// Return `false` if the process has already terminated.
fn EventBus::register_pid(self : EventBus, pid : Int32) -> Bool raise {
  let ret = self.register_pid_ffi(pid)
  if ret == -1 {
    @os_error.check_errno("poll_register_pid")
  }
  ret > 0
}

///|
#warnings("-unused_error_type")
fn EventBus::remove(_self : EventBus, _fd : @fd_util.Fd) -> Unit raise {
  // TODO: add explicit unregister support for Wasm on Linux
}
