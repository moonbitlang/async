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
#cfg(any(target="wasm", platform="windows"))
fn IoResult::cancel(
  self : IoResult,
  handle : @fd_util.Fd,
  context~ : String,
) -> CancellationStatus raise {
  let ret = self.cancel_ffi(handle)
  if ret < 0 {
    @os_error.check_errno(context)
  }
  if ret == 1 {
    NeedWait
  } else {
    NoWait
  }
}

///|
#cfg(any(target="wasm", platform="windows"))
fn IoResult::status(
  result : IoResult,
  handle : @fd_util.Fd,
  context~ : String,
) -> Int raise {
  let n = result.status_ffi(handle)
  if n < 0 {
    if errno_is_cancelled(@os_error.get_errno()) {
      raise @coroutine.Cancelled
    } else {
      @os_error.check_errno(context)
    }
  }
  n
}

///|
#cfg(any(target="wasm", platform="windows"))
async fn IoHandle::wait_read_result(
  handle : IoHandle,
  io_result : IoResult,
  context~ : String,
  loc~ : SourceLoc,
) -> Unit {
  guard curr_loop.val is Some(evloop)
  guard handle.read is Idle
  handle.read = Waiting(@coroutine.current_coroutine())
  defer {
    handle.read = Idle
  }
  evloop.suspend(loc~) catch {
    _ => wait_for_cancellation(() => io_result.cancel(handle.fd, context~))
  }
}

///|
#cfg(any(target="wasm", platform="windows"))
async fn IoHandle::wait_write_result(
  handle : IoHandle,
  io_result : IoResult,
  context~ : String,
  loc~ : SourceLoc,
) -> Unit {
  guard curr_loop.val is Some(evloop)
  guard handle.write is Idle
  handle.write = Waiting(@coroutine.current_coroutine())
  defer {
    handle.write = Idle
  }
  evloop.suspend(loc~) catch {
    _ => wait_for_cancellation(() => io_result.cancel(handle.fd, context~))
  }
}

///|
#cfg(platform="windows")
extern "C" fn read_windows(fd : @fd_util.Fd, result : IoResult) -> Int = "moonbitlang_async_read"

///|
#cfg(target="wasm")
#unsafe_skip_stub_check
fn read_io_result_ffi(fd : @fd_util.Fd, result : IoResultHandle) -> Int = "moonbitlang/async" "io/read/windows"

///|
#cfg(target="wasm")
fn read_windows(fd : @fd_util.Fd, result : IoResult) -> Int {
  read_io_result_ffi(fd, result.handle)
}

///|
#cfg(platform="windows")
extern "C" fn errno_is_read_eof(errno : Int) -> Bool = "moonbitlang_async_errno_is_read_EOF"

///|
#cfg(target="wasm")
#unsafe_skip_stub_check
fn errno_is_read_eof(errno : Int) -> Bool = "moonbitlang/async" "io/errno_is_read_EOF/windows"

///|
#cfg(any(target="wasm", platform="windows"))
async fn IoHandle::generic_read_windows(
  handle : IoHandle,
  result : IoResult,
  context~ : String,
  loc~ : SourceLoc,
) -> Int {
  let n = read_windows(handle.fd, result)
  let n = if n >= 0 {
    // The `pause` here prevent a busy read loop from exhausting the whole program,
    // and give chance for other tasks to execute.
    @coroutine.protect_from_cancel(
      () => @coroutine.pause(loc~),
      resume_on_cancel=true,
    )
    // It is important to note that the logic here is correct
    // only if `FILE_SKIP_COMPLETION_PORT_ON_SUCCESS` is set
    // via `SetFileCompletionNotificationModes`.
    // Otherwise, even if the read operation itself indicates immediate success,
    // we still need to wait for the completion packet to obtain correct result.
    n
  } else if @os_error.is_nonblocking_io_error() {
    handle.wait_read_result(result, context~, loc~)
    result.status(handle.fd, context~) catch {
      @os_error.OSError(errno, ..) if errno_is_read_eof(errno) => 0
      err => raise err
    }
  } else if errno_is_read_eof(@os_error.get_errno()) {
    0
  } else {
    @os_error.check_errno(context)
    panic()
  }
  result.copy_read_result(n)
  n
}

///|
#cfg(any(target="wasm", platform="windows"))
async fn IoHandle::read_via_event_bus_windows(
  handle : IoHandle,
  buf : FixedArray[Byte],
  offset~ : Int,
  len~ : Int,
  context~ : String,
  loc~ : SourceLoc,
) -> Int {
  let result = match handle.kind {
    Regular => panic()
    Socket => IoResult::for_socket_read(buf, offset~, len~, flags=0)
    _ => IoResult::for_file_read(buf, offset~, len~, position=0)
  }
  defer result.free()
  handle.generic_read_windows(result, context~, loc~)
}

///|
#cfg(platform="windows")
async fn IoHandle::read_via_event_bus(
  handle : IoHandle,
  buf : FixedArray[Byte],
  offset~ : Int,
  len~ : Int,
  context~ : String,
  loc~ : SourceLoc,
) -> Int {
  handle.read_via_event_bus_windows(buf, offset~, len~, context~, loc~)
}

///|
#cfg(platform="windows")
extern "C" fn write_windows(fd : @fd_util.Fd, result : IoResult) -> Int = "moonbitlang_async_write"

///|
#cfg(target="wasm")
#unsafe_skip_stub_check
fn write_io_result_ffi(fd : @fd_util.Fd, result : IoResultHandle) -> Int = "moonbitlang/async" "io/write/windows"

///|
#cfg(target="wasm")
fn write_windows(fd : @fd_util.Fd, result : IoResult) -> Int {
  write_io_result_ffi(fd, result.handle)
}

///|
#cfg(any(target="wasm", platform="windows"))
async fn IoHandle::generic_write_windows(
  handle : IoHandle,
  result : IoResult,
  context~ : String,
  loc~ : SourceLoc,
) -> Int {
  let n = write_windows(handle.fd, result)
  if n >= 0 {
    // The `pause` here prevent a busy write loop from exhausting the whole program,
    // and give chance for other tasks to execute.
    @coroutine.protect_from_cancel(
      () => @coroutine.pause(loc~),
      resume_on_cancel=true,
    )
    // It is important to note that the logic here is correct
    // only if `FILE_SKIP_COMPLETION_PORT_ON_SUCCESS` is set
    // via `SetFileCompletionNotificationModes`.
    // Otherwise, even if the write operation itself indicates immediate success,
    // we still need to wait for the completion packet to obtain correct result.
    n
  } else if @os_error.is_nonblocking_io_error() {
    handle.wait_write_result(result, context~, loc~)
    result.status(handle.fd, context~)
  } else {
    @os_error.check_errno(context)
    panic()
  }
}

///|
#cfg(any(target="wasm", platform="windows"))
async fn IoHandle::write_via_event_bus_windows(
  handle : IoHandle,
  buf : Bytes,
  offset~ : Int,
  len~ : Int,
  context~ : String,
  loc~ : SourceLoc,
) -> Int {
  let result = match handle.kind {
    Regular => panic()
    Socket => IoResult::for_socket_write(buf, offset~, len~, flags=0)
    _ => IoResult::for_file_write(buf, offset~, len~, position=0)
  }
  defer result.free()
  handle.generic_write_windows(result, context~, loc~)
}

///|
#cfg(platform="windows")
async fn IoHandle::write_via_event_bus(
  handle : IoHandle,
  buf : Bytes,
  offset~ : Int,
  len~ : Int,
  context~ : String,
  loc~ : SourceLoc,
) -> Int {
  handle.write_via_event_bus_windows(buf, offset~, len~, context~, loc~)
}
