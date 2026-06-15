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
extern "C" fn kind_of_fd_sync_ffi(fd : @fd_util.Fd) -> Int = "moonbitlang_async_kind_of_fd"

///|
fn kind_of_fd_sync(
  fd : @fd_util.Fd,
  context~ : String,
) -> @fd_util.FileKind raise {
  let kind = kind_of_fd_sync_ffi(fd)
  if kind < 0 {
    @os_error.check_errno(context)
  }
  @fd_util.FileKind::unsafe_from_int(kind)
}

///|
#cfg(not(platform="windows"))
fn setup_stdio(fd : Int, context~ : String) -> IoHandle raise {
  let kind = kind_of_fd_sync(fd, context~)
  let is_async = @fd_util.fd_is_nonblocking(fd, context~)
  let handle = { fd, kind, is_async, events: NoEvent, read: None, write: None }
  register_hook(
    init=() => {
      guard curr_loop.val is Some(evloop)
      guard evloop.backend.fds.get(fd) is None
      evloop.backend.fds[fd] = handle
    },
    exit=() => {
      handle.detach_from_event_loop()
      handle.events = NoEvent
    },
  )
  handle
}

///|
#cfg(platform="windows")
extern "C" fn get_std_handle(id : Int) -> @fd_util.Fd = "moonbitlang_async_get_std_handle"

///|
#cfg(platform="windows")
let stdio_handles : Map[@fd_util.Fd, IoHandle] = {}

///|
#cfg(platform="windows")
fn setup_stdio(id : Int, context~ : String) -> IoHandle raise {
  // The value comes from https://learn.microsoft.com/en-us/windows/console/getstdhandle
  let fd = get_std_handle(-10 - id)
  if !@fd_util.fd_is_valid(fd) {
    @os_error.check_errno(context)
  }
  if stdio_handles.get(fd) is Some(handle) {
    // when `stdout` and `stderr` are redirected to the same file/pipe,
    // `GetStdHande` will return the same handle for them.
    // In this case, avoid problem caused by duplicated handle value
    return handle
  }
  let kind = kind_of_fd_sync(fd, context~)
  let handle = {
    fd,
    kind,
    is_async: false,
    reading: false,
    read_offset: 0,
    writing: false,
    write_offset: 0,
  }
  stdio_handles[fd] = handle

  // register stdio on event loop creation.
  // This allows multiple event loop inside a single program.
  register_hook(
    init=() => {
      guard curr_loop.val is Some(evloop)
      guard evloop.backend.fds.get(fd) is None
      evloop.backend.fds[fd] = handle
    },
    exit=() => handle.detach_from_event_loop(),
  )
  handle
}

///|
pub let stdin : Result[IoHandle, Error] = try
  setup_stdio(0, context="initialize `stdin`")
catch {
  err => Err(err)
} noraise {
  handle => Ok(handle)
}

///|
pub let stdout : Result[IoHandle, Error] = try
  setup_stdio(1, context="initialize `stdout`")
catch {
  err => Err(err)
} noraise {
  handle => Ok(handle)
}

///|
pub let stderr : Result[IoHandle, Error] = try
  setup_stdio(2, context="initialize `stderr`")
catch {
  err => Err(err)
} noraise {
  handle => Ok(handle)
}
