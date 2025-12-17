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
#cfg(not(platform="windows"))
const NoEvent = 0

///|
#cfg(not(platform="windows"))
const ReadEvent = 1

///|
#cfg(not(platform="windows"))
const WriteEvent = 2

///|
#cfg(not(platform="windows"))
const ProcessEvent = 4

///|
extern "C" fn Instance::new() -> Instance = "moonbitlang_async_poll_create"

///|
extern "C" fn Instance::destroy(self : Instance) = "moonbitlang_async_poll_destroy"

///|
#cfg(not(platform="windows"))
extern "C" fn Instance::register_ffi(
  self : Instance,
  fd : @fd_util.Fd,
  prev_events~ : Int,
  new_events~ : Int,
  oneshot~ : Bool,
) -> Int = "moonbitlang_async_poll_register"

///|
#cfg(not(platform="windows"))
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
#cfg(platform="windows")
extern "C" fn Instance::register_ffi(self : Instance, fd : @fd_util.Fd) -> Int = "moonbitlang_async_poll_register"

///|
#cfg(platform="windows")
fn Instance::register(self : Instance, fd : @fd_util.Fd) -> Unit raise {
  if self.register_ffi(fd) < 0 {
    @os_error.check_errno("poll_register")
  }
}

///|
#cfg(not(platform="windows"))
extern "C" fn Instance::register_pid_ffi(self : Instance, pid : Int) -> Int = "moonbitlang_async_poll_register_pid"

///|
#cfg(not(platform="windows"))
priv enum RegisterPidResult {
  Running(Int)
  Stopped
}

///|
#cfg(not(platform="windows"))
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
#cfg(not(platform="windows"))
extern "C" fn Instance::remove_ffi(
  self : Instance,
  fd : @fd_util.Fd,
  events~ : Int,
) -> Int = "moonbitlang_async_poll_remove"

///|
#cfg(not(platform="windows"))
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
#cfg(not(platform="windows"))
extern "C" fn Instance::remove_pid_ffi(
  self : Instance,
  pid_handle : Int,
) -> Int = "moonbitlang_async_poll_remove_pid"

///|
#cfg(not(platform="windows"))
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
#cfg(not(platform="windows"))
extern "C" fn Event::events(self : Event) -> Int = "moonbitlang_async_event_get_events"

///|
#cfg(platform="windows")
#external
priv type IoResult

///|
#cfg(platform="windows")
#owned(buf)
extern "C" fn IoResult::for_file(
  job_id : Int,
  buf : Bytes,
  offset~ : Int,
  len~ : Int,
  position~ : Int64,
) -> IoResult = "moonbitlang_async_make_file_io_result"

///|
#cfg(platform="windows")
#owned(buf)
extern "C" fn IoResult::for_socket(
  job_id : Int,
  buf : Bytes,
  offset~ : Int,
  len~ : Int,
  flags~ : Int,
) -> IoResult = "moonbitlang_async_make_socket_io_result"

///|
#cfg(platform="windows")
#owned(buf, addr)
extern "C" fn IoResult::for_socket_with_addr(
  job_id : Int,
  buf : Bytes,
  offset~ : Int,
  len~ : Int,
  flags~ : Int,
  addr~ : Bytes,
) -> IoResult = "moonbitlang_async_make_socket_with_addr_io_result"

///|
#cfg(platform="windows")
#owned(addr)
extern "C" fn IoResult::for_connect(job_id : Int, addr : Bytes) -> IoResult = "moonbitlang_async_make_connect_io_result"

///|
#cfg(platform="windows")
extern "C" fn IoResult::for_accept(job_id : Int) -> IoResult = "moonbitlang_async_make_accept_io_result"

///|
#cfg(platform="windows")
extern "C" fn IoResult::free(self : IoResult) = "moonbitlang_async_free_io_result"

///|
#cfg(platform="windows")
extern "C" fn IoResult::job_id(self : IoResult) -> Int = "moonbitlang_async_io_result_get_job_id"

///|
#cfg(platform="windows")
extern "C" fn IoResult::cancel_ffi(
  self : IoResult,
  handle : @fd_util.Fd,
) -> Int = "moonbitlang_async_cancel_io_result"

///|
#cfg(platform="windows")
fn IoResult::cancel(
  self : IoResult,
  handle : @fd_util.Fd,
  context~ : String,
) -> Unit raise {
  if 0 == self.cancel_ffi(handle) {
    @os_error.check_errno(context)
  }
}

///|
#cfg(platform="windows")
extern "C" fn IoResult::status_ffi(
  result : IoResult,
  handle : @fd_util.Fd,
) -> Int = "moonbitlang_async_io_result_get_status"

///|
#cfg(platform="windows")
fn IoResult::status(
  result : IoResult,
  handle : @fd_util.Fd,
  context~ : String,
) -> Int raise {
  let n = result.status_ffi(handle)
  if n < 0 {
    @os_error.check_errno(context)
  }
  n
}

///|
#cfg(platform="windows")
extern "C" fn Event::io_result(self : Event) -> IoResult = "moonbitlang_async_event_get_io_result"

///|
#cfg(platform="windows")
extern "C" fn Event::bytes_transferred(self : Event) -> Int = "moonbitlang_async_event_get_bytes_transferred"

///|
extern "C" fn Instance::wait(self : Instance, timeout~ : Int) -> Int = "moonbitlang_async_poll_wait"
