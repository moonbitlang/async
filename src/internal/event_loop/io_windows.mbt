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
#cfg(platform="windows")
#external
priv type IoResult

///|
#cfg(platform="windows")
#owned(buf)
extern "C" fn IoResult::for_file(
  events : Int,
  buf : Bytes,
  offset~ : Int,
  len~ : Int,
  position~ : Int64,
) -> IoResult = "moonbitlang_async_make_file_io_result"

///|
#cfg(platform="windows")
#owned(buf)
extern "C" fn IoResult::for_socket(
  events : Int,
  buf : Bytes,
  offset~ : Int,
  len~ : Int,
  flags~ : Int,
) -> IoResult = "moonbitlang_async_make_socket_io_result"

///|
#cfg(platform="windows")
#owned(buf, addr)
extern "C" fn IoResult::for_socket_with_addr(
  events : Int,
  buf : Bytes,
  offset~ : Int,
  len~ : Int,
  flags~ : Int,
  addr~ : Bytes,
) -> IoResult = "moonbitlang_async_make_socket_with_addr_io_result"

///|
#cfg(platform="windows")
#owned(addr)
extern "C" fn IoResult::for_connect(addr : Bytes) -> IoResult = "moonbitlang_async_make_connect_io_result"

///|
#cfg(platform="windows")
extern "C" fn IoResult::for_accept() -> IoResult = "moonbitlang_async_make_accept_io_result"

///|
#cfg(platform="windows")
#owned(buf)
extern "C" fn IoResult::for_read_dir_changes(
  buf : Bytes,
  len~ : Int,
) -> IoResult = "moonbitlang_async_make_read_dir_changes_io_result"

///|
#cfg(platform="windows")
extern "C" fn IoResult::free(self : IoResult) = "moonbitlang_async_free_io_result"

///|
#cfg(platform="windows")
extern "C" fn IoResult::event(self : IoResult) -> Int = "moonbitlang_async_io_result_get_event"

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
    if errno_is_cancelled(@os_error.get_errno()) {
      raise @coroutine.Cancelled
    } else {
      @os_error.check_errno(context)
    }
  }
  n
}

///|
#cfg(platform="windows")
async fn IoHandle::wait_read(
  handle : IoHandle,
  io_result : IoResult,
  context~ : String,
) -> Unit {
  guard handle.read is Idle
  handle.read = Waiting(@coroutine.current_coroutine())
  defer {
    handle.read = Idle
  }
  @coroutine.suspend() catch {
    err => {
      if io_result.cancel(handle.fd, context~) is NeedWait {
        @coroutine.protect_from_cancel(@coroutine.suspend)
      }
      raise err
    }
  }
}

///|
#cfg(platform="windows")
async fn IoHandle::wait_write(
  handle : IoHandle,
  io_result : IoResult,
  context~ : String,
) -> Unit {
  guard handle.write is Idle
  handle.write = Waiting(@coroutine.current_coroutine())
  defer {
    handle.write = Idle
  }
  @coroutine.suspend() catch {
    err => {
      if io_result.cancel(handle.fd, context~) is NeedWait {
        @coroutine.protect_from_cancel(@coroutine.suspend)
      }
      raise err
    }
  }
}

///|
#cfg(platform="windows")
extern "C" fn read_ffi(fd : @fd_util.Fd, result : IoResult) -> Int = "moonbitlang_async_read"

///|
#cfg(platform="windows")
extern "C" fn errno_is_read_eof(errno : Int) -> Bool = "moonbitlang_async_errno_is_read_EOF"

///|
#cfg(platform="windows")
async fn IoHandle::generic_read(
  handle : IoHandle,
  result : IoResult,
  context~ : String,
) -> Int {
  let n = read_ffi(handle.fd, result)
  if n >= 0 {
    // It is important to note that the logic here is correct
    // only if `FILE_SKIP_COMPLETION_PORT_ON_SUCCESS` is set
    // via `SetFileCompletionNotificationModes`.
    // Otherwise, even if the read operation itself indicates immediate success,
    // we still need to wait for the completion packet to obtain correct result.
    @coroutine.pause()
    n
  } else if @os_error.is_nonblocking_io_error() {
    handle.wait_read(result, context~)
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
}

///|
#cfg(platform="windows")
async fn IoHandle::read_via_event_bus(
  handle : IoHandle,
  buf : FixedArray[Byte],
  offset~ : Int,
  len~ : Int,
  context~ : String,
) -> Int {
  let result = match handle.kind {
    Regular => panic()
    Socket =>
      IoResult::for_socket(
        ReadEvent,
        buf.unsafe_reinterpret_as_bytes(),
        offset~,
        len~,
        flags=0,
      )
    _ =>
      IoResult::for_file(
        ReadEvent,
        buf.unsafe_reinterpret_as_bytes(),
        offset~,
        len~,
        position=0,
      )
  }
  defer result.free()
  handle.generic_read(result, context~)
}

///|
#cfg(platform="windows")
extern "C" fn write_ffi(fd : @fd_util.Fd, result : IoResult) -> Int = "moonbitlang_async_write"

///|
#cfg(platform="windows")
async fn IoHandle::generic_write(
  handle : IoHandle,
  result : IoResult,
  context~ : String,
) -> Int {
  let n = write_ffi(handle.fd, result)
  if n >= 0 {
    @coroutine.pause()
    // It is important to note that the logic here is correct
    // only if `FILE_SKIP_COMPLETION_PORT_ON_SUCCESS` is set
    // via `SetFileCompletionNotificationModes`.
    // Otherwise, even if the write operation itself indicates immediate success,
    // we still need to wait for the completion packet to obtain correct result.
    n
  } else if @os_error.is_nonblocking_io_error() {
    handle.wait_write(result, context~)
    result.status(handle.fd, context~)
  } else {
    @os_error.check_errno(context)
    panic()
  }
}

///|
#cfg(platform="windows")
async fn IoHandle::write_via_event_bus(
  handle : IoHandle,
  buf : Bytes,
  offset~ : Int,
  len~ : Int,
  context~ : String,
) -> Int {
  let result = match handle.kind {
    Regular => panic()
    Socket => IoResult::for_socket(WriteEvent, buf, offset~, len~, flags=0)
    _ => IoResult::for_file(WriteEvent, buf, offset~, len~, position=0)
  }
  defer result.free()
  handle.generic_write(result, context~)
}
