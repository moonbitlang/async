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
/// The main event bus for receiving various notifications
/// This is what the main event loop iterates over.
/// Implementation:
///
/// - Linux: epoll
/// - MacOS: kqueue
/// - Windows: IOCP
priv struct EventBus(@fd_util.Fd)

///|
const ReadEvent = 1

///|
const WriteEvent = 2

///|
#cfg(not(platform="windows"))
const ProcessEvent = 4

///|
extern "C" fn EventBus::new() -> EventBus = "moonbitlang_async_event_bus_create"

///|
extern "C" fn EventBus::destroy(self : EventBus) = "moonbitlang_async_event_bus_destroy"

///|
extern "C" fn EventBus::register_ffi(
  self : EventBus,
  fd : @fd_util.Fd,
  read_only : Bool,
) -> Int = "moonbitlang_async_event_bus_register"

///|
fn EventBus::register(
  self : EventBus,
  fd : @fd_util.Fd,
  read_only~ : Bool,
) -> Unit raise {
  if self.register_ffi(fd, read_only) < 0 {
    @os_error.check_errno("runtime internal: @event_loop.EventBus::register()")
  }
}

///|
/// On Linux <5.3, `pidfd` is not supported,
/// hence we cannot wait for a process via `epoll`.
#cfg(not(platform="windows"))
extern "C" fn detect_wait_pid_via_event_bus() -> Bool = "moonbitlang_async_support_wait_pid_via_event_bus"

///|
#cfg(not(platform="windows"))
let support_wait_pid_via_event_bus : Bool = detect_wait_pid_via_event_bus()

///|
#cfg(not(platform="windows"))
extern "C" fn EventBus::register_pid_ffi(self : EventBus, pid : Int) -> Int = "moonbitlang_async_event_bus_register_pid"

///|
#cfg(not(platform="windows"))
priv enum RegisterPidResult {
  Running(Int)
  Stopped
}

///|
#cfg(not(platform="windows"))
fn EventBus::register_pid(
  self : EventBus,
  pid : Int,
) -> RegisterPidResult raise {
  let ret = self.register_pid_ffi(pid)
  if ret >= 0 {
    Running(ret)
  } else if ret == -2 {
    Stopped
  } else {
    @os_error.check_errno("poll_register_pid")
    Stopped
  }
}

///|
#external
priv type Event

///|
extern "C" fn get_event(index : Int) -> Event = "moonbitlang_async_event_list_get"

///|
extern "C" fn Event::fd(self : Event) -> @fd_util.Fd = "moonbitlang_async_event_get_fd"

///|
#cfg(not(platform="windows"))
extern "C" fn Event::events(self : Event) -> Int = "moonbitlang_async_event_get_events"

///|
#cfg(platform="windows")
extern "C" fn Event::io_result(self : Event) -> IoResult = "moonbitlang_async_event_get_io_result"

///|
#cfg(platform="windows")
extern "C" fn Event::bytes_transferred(self : Event) -> Int = "moonbitlang_async_event_get_bytes_transferred"

///|
extern "C" fn EventBus::wait(self : EventBus, timeout~ : Int) -> Int = "moonbitlang_async_event_bus_wait"
