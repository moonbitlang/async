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
pub async fn IoHandle::wait_read(handle : IoHandle) -> Unit {
  guard @fd_util.fd_is_valid(handle.fd) else {
    abort("file descriptor already closed")
  }
  guard handle.read is Idle
  handle.read = Waiting(@coroutine.current_coroutine())
  defer {
    handle.read = Idle
  }
  @coroutine.suspend()
}

///|
async fn IoHandle::wait_write(handle : IoHandle) -> Unit {
  guard @fd_util.fd_is_valid(handle.fd) else {
    abort("file descriptor already closed")
  }
  guard handle.write is Idle
  handle.write = Waiting(@coroutine.current_coroutine())
  defer {
    handle.write = Idle
  }
  @coroutine.suspend()
}

///|
#unsafe_skip_stub_check
#borrow(buf)
fn read_ffi(
  fd : @fd_util.Fd,
  buf : FixedArray[Byte],
  offset~ : Int,
  len~ : Int,
) -> Int = "moonbitlang/async" "io/read/unix"

///|
async fn IoHandle::read_via_event_bus_unix(
  handle : IoHandle,
  buf : FixedArray[Byte],
  offset~ : Int,
  len~ : Int,
  context~ : String,
) -> Int {
  let ret = read_ffi(handle.fd, buf, offset~, len~)
  if ret >= 0 {
    // The `pause` here prevent a busy read loop from exhausting the whole program,
    // and give chance for other tasks to execute.
    @coroutine.protect_from_cancel(@coroutine.pause, resume_on_cancel=true)
    return ret
  }
  let ret = if @os_error.is_nonblocking_io_error() {
    handle.wait_read()
    read_ffi(handle.fd, buf, offset~, len~)
  } else {
    ret
  }
  if ret < 0 {
    @os_error.check_errno(context)
  }
  ret
}

///|
#unsafe_skip_stub_check
#borrow(buf)
fn write_ffi(fd : @fd_util.Fd, buf : Bytes, offset~ : Int, len~ : Int) -> Int = "moonbitlang/async" "io/write/unix"

///|
async fn IoHandle::write_via_event_bus_unix(
  handle : IoHandle,
  buf : Bytes,
  offset~ : Int,
  len~ : Int,
  context~ : String,
) -> Int {
  let ret = write_ffi(handle.fd, buf, offset~, len~)
  if ret >= 0 {
    // The `pause` here prevent a busy write loop from exhausting the whole program,
    // and give chance for other tasks to execute.
    @coroutine.protect_from_cancel(@coroutine.pause, resume_on_cancel=true)
    return ret
  }
  let ret = if @os_error.is_nonblocking_io_error() {
    handle.wait_write()
    write_ffi(handle.fd, buf, offset~, len~)
  } else {
    ret
  }
  if ret < 0 {
    @os_error.check_errno(context)
  }
  ret
}

///|
priv struct IoResult(UInt64)

///|
#unsafe_skip_stub_check
fn IoResult::for_file_read(len~ : Int, position~ : Int64) -> IoResult = "moonbitlang/async" "io/make_file_read_io_result/windows"

///|
#unsafe_skip_stub_check
#borrow(buf)
fn IoResult::for_file_write(
  buf : Bytes,
  offset~ : Int,
  len~ : Int,
  position~ : Int64,
) -> IoResult = "moonbitlang/async" "io/make_file_write_io_result/windows"

///|
#unsafe_skip_stub_check
fn IoResult::for_socket_read(len~ : Int, flags~ : Int) -> IoResult = "moonbitlang/async" "io/make_socket_read_io_result/windows"

///|
#unsafe_skip_stub_check
#borrow(buf)
fn IoResult::for_socket_write(
  buf : Bytes,
  offset~ : Int,
  len~ : Int,
  flags~ : Int,
) -> IoResult = "moonbitlang/async" "io/make_socket_write_io_result/windows"

///|
#unsafe_skip_stub_check
#borrow(addr)
fn IoResult::for_socket_with_addr_read(
  len~ : Int,
  flags~ : Int,
  addr~ : Bytes,
  addr_len? : Int = addr.length(),
) -> IoResult = "moonbitlang/async" "io/make_socket_with_addr_read_io_result/windows"

///|
#unsafe_skip_stub_check
#borrow(buf, addr)
fn IoResult::for_socket_with_addr_write(
  buf : Bytes,
  offset~ : Int,
  len~ : Int,
  flags~ : Int,
  addr~ : Bytes,
  addr_len? : Int = addr.length(),
) -> IoResult = "moonbitlang/async" "io/make_socket_with_addr_write_io_result/windows"

///|
#unsafe_skip_stub_check
#borrow(addr)
fn IoResult::for_connect(
  addr : Bytes,
  addr_len? : Int = addr.length(),
) -> IoResult = "moonbitlang/async" "io/make_connect_io_result/windows"

///|
#unsafe_skip_stub_check
fn IoResult::for_accept(addr_len : Int) -> IoResult = "moonbitlang/async" "io/make_accept_io_result/windows"

///|
#unsafe_skip_stub_check
#borrow(dst)
fn IoResult::get_accept_peer_addr(
  self : IoResult,
  dst : Bytes,
  dst_len? : Int = dst.length(),
) -> Unit = "moonbitlang/async" "io/get_accept_peer_addr/windows"

///|
#unsafe_skip_stub_check
fn IoResult::free(self : IoResult) -> Unit = "moonbitlang/async" "io/free_io_result/windows"

///|
#unsafe_skip_stub_check
fn IoResult::event(self : IoResult) -> Int = "moonbitlang/async" "io/io_result_get_event/windows"

///|
#unsafe_skip_stub_check
fn IoResult::cancel_ffi(self : IoResult, handle : @fd_util.Fd) -> Int = "moonbitlang/async" "io/cancel_io_result/windows"

///|
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
#unsafe_skip_stub_check
fn IoResult::status_ffi(result : IoResult, handle : @fd_util.Fd) -> Int = "moonbitlang/async" "io/io_result_get_status/windows"

///|
#unsafe_skip_stub_check
#borrow(dst)
fn IoResult::copy_read(
  result : IoResult,
  dst : FixedArray[Byte],
  offset~ : Int,
  len~ : Int,
) -> Unit = "moonbitlang/async" "io/io_result_copy_read/windows"

///|
#unsafe_skip_stub_check
#borrow(dst, addr)
fn IoResult::copy_read_with_addr(
  result : IoResult,
  dst : FixedArray[Byte],
  offset~ : Int,
  len~ : Int,
  addr~ : Bytes,
  addr_len? : Int = addr.length(),
) -> Unit = "moonbitlang/async" "io/io_result_copy_read_with_addr/windows"

///|
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
async fn IoHandle::wait_read_result(
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
async fn IoHandle::wait_write_result(
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
#unsafe_skip_stub_check
fn read_io_result_ffi(fd : @fd_util.Fd, result : IoResult) -> Int = "moonbitlang/async" "io/read/windows"

///|
#unsafe_skip_stub_check
fn errno_is_read_eof(errno : Int) -> Bool = "moonbitlang/async" "io/errno_is_read_EOF/windows"

///|
async fn IoHandle::read_io_result_windows(
  handle : IoHandle,
  result : IoResult,
  context~ : String,
) -> Int {
  let n = read_io_result_ffi(handle.fd, result)
  if n >= 0 {
    // The `pause` here prevent a busy read loop from exhausting the whole program,
    // and give chance for other tasks to execute.
    @coroutine.protect_from_cancel(@coroutine.pause, resume_on_cancel=true)
    n
  } else if @os_error.is_nonblocking_io_error() {
    handle.wait_read_result(result, context~)
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
async fn IoHandle::generic_read_windows(
  handle : IoHandle,
  result : IoResult,
  buf : FixedArray[Byte],
  offset~ : Int,
  context~ : String,
) -> Int {
  let n = handle.read_io_result_windows(result, context~)
  result.copy_read(buf, offset~, len=n)
  n
}

///|
async fn IoHandle::generic_read_with_addr_windows(
  handle : IoHandle,
  result : IoResult,
  buf : FixedArray[Byte],
  offset~ : Int,
  addr~ : Bytes,
  context~ : String,
) -> Int {
  let n = handle.read_io_result_windows(result, context~)
  result.copy_read_with_addr(buf, offset~, len=n, addr~)
  n
}

///|
async fn IoHandle::read_via_event_bus_windows(
  handle : IoHandle,
  buf : FixedArray[Byte],
  offset~ : Int,
  len~ : Int,
  context~ : String,
) -> Int {
  let result = match handle.kind {
    Regular => panic()
    Socket => IoResult::for_socket_read(len~, flags=0)
    _ => IoResult::for_file_read(len~, position=0)
  }
  defer result.free()
  handle.generic_read_windows(result, buf, offset~, context~)
}

///|
async fn IoHandle::read_via_event_bus(
  handle : IoHandle,
  buf : FixedArray[Byte],
  offset~ : Int,
  len~ : Int,
  context~ : String,
) -> Int {
  if platform is Windows {
    handle.read_via_event_bus_windows(buf, offset~, len~, context~)
  } else {
    handle.read_via_event_bus_unix(buf, offset~, len~, context~)
  }
}

///|
#unsafe_skip_stub_check
fn write_io_result_ffi(fd : @fd_util.Fd, result : IoResult) -> Int = "moonbitlang/async" "io/write/windows"

///|
async fn IoHandle::generic_write_windows(
  handle : IoHandle,
  result : IoResult,
  context~ : String,
) -> Int {
  let n = write_io_result_ffi(handle.fd, result)
  if n >= 0 {
    // The `pause` here prevent a busy write loop from exhausting the whole program,
    // and give chance for other tasks to execute.
    @coroutine.protect_from_cancel(@coroutine.pause, resume_on_cancel=true)
    n
  } else if @os_error.is_nonblocking_io_error() {
    handle.wait_write_result(result, context~)
    result.status(handle.fd, context~)
  } else {
    @os_error.check_errno(context)
    panic()
  }
}

///|
async fn IoHandle::write_via_event_bus_windows(
  handle : IoHandle,
  buf : Bytes,
  offset~ : Int,
  len~ : Int,
  context~ : String,
) -> Int {
  let result = match handle.kind {
    Regular => panic()
    Socket => IoResult::for_socket_write(buf, offset~, len~, flags=0)
    _ => IoResult::for_file_write(buf, offset~, len~, position=0)
  }
  defer result.free()
  handle.generic_write_windows(result, context~)
}

///|
async fn IoHandle::write_via_event_bus(
  handle : IoHandle,
  buf : Bytes,
  offset~ : Int,
  len~ : Int,
  context~ : String,
) -> Int {
  if platform is Windows {
    handle.write_via_event_bus_windows(buf, offset~, len~, context~)
  } else {
    handle.write_via_event_bus_unix(buf, offset~, len~, context~)
  }
}
