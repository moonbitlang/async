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
priv struct Instance(@fd_util.Fd)

///|
const NoEvent = 0

///|
const ReadEvent = 1

///|
const WriteEvent = 2

///|
const ProcessEvent = 4

///|
extern "C" fn Instance::new() -> Instance = "moonbitlang_async_poll_create"

///|
extern "C" fn Instance::destroy(self : Instance) = "moonbitlang_async_poll_destroy"

///|
extern "C" fn Instance::register_ffi(
  self : Instance,
  fd : @fd_util.Fd,
  prev_events~ : Int,
  new_events~ : Int,
  oneshot~ : Bool,
) -> Int = "moonbitlang_async_poll_register"

///|
fn Instance::register(
  self : Instance,
  fd : @fd_util.Fd,
  prev_events~ : Int,
  new_events~ : Int,
  oneshot? : Bool = false,
) -> Unit raise {
  if self.register_ffi(fd, prev_events~, new_events~, oneshot~) < 0 {
    @os_error.check_errno("poll_register")
  }
}

///|
extern "C" fn Instance::register_pid_ffi(self : Instance, pid : Int) -> Int = "moonbitlang_async_poll_register_pid"

///|
priv enum RegisterPidResult {
  Running(Int)
  Stopped
}

///|
fn Instance::register_pid(
  self : Instance,
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
extern "C" fn Instance::remove_ffi(
  self : Instance,
  fd : @fd_util.Fd,
  events~ : Int,
) -> Int = "moonbitlang_async_poll_remove"

///|
fn Instance::remove(
  self : Instance,
  fd : @fd_util.Fd,
  events~ : Int,
) -> Unit raise {
  if 0 != self.remove_ffi(fd, events~) {
    @os_error.check_errno("poll_remove")
  }
}

///|
extern "C" fn Instance::remove_pid_ffi(
  self : Instance,
  pid_handle : Int,
) -> Int = "moonbitlang_async_poll_remove_pid"

///|
fn Instance::remove_pid(self : Instance, pid_handle : Int) -> Unit {
  if 0 != self.remove_pid_ffi(pid_handle) {
    @os_error.check_errno("poll_remove_pid") catch {
      err => abort(err.to_string())
    }
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
extern "C" fn Event::events(self : Event) -> Int = "moonbitlang_async_event_get_events"

///|
extern "C" fn Instance::wait(self : Instance, timeout~ : Int) -> Int = "moonbitlang_async_poll_wait"
