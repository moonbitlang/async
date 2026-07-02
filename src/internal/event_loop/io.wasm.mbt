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
priv struct IoResultHandle(UInt64)

///|
/// In WASM backend, letting overlapped Windows syscall hold reference to
/// (mapped) physical address of WASM memory is unsafe,
/// because `memory.grow` may change the base address of WASM memory.
/// Hence for all output buffer passed to overlapped Windows syscall,
/// we need to allocate a temporary buffer in the runtime instead,
/// and copy output data to the MoonBit buffer only after job completion.
/// To align with native API, this copy phase is implemented as a callback.
#valtype
priv struct IoResult {
  handle : IoResultHandle
  copy_output : ((IoResultHandle) -> Unit)?
}

///|
fn IoResult::IoResult(
  handle : IoResultHandle,
  copy_output? : (IoResultHandle) -> Unit,
) -> IoResult {
  { handle, copy_output }
}

///|
#unsafe_skip_stub_check
fn IoResultHandle::for_file_read(
  len~ : Int,
  position~ : Int64,
) -> IoResultHandle = "moonbitlang/async" "io/make_file_read_io_result/windows"

///|
#unsafe_skip_stub_check
#borrow(dst)
fn IoResultHandle::copy_read(
  result : IoResultHandle,
  dst : FixedArray[Byte],
  offset~ : Int,
  len~ : Int,
) -> Unit = "moonbitlang/async" "io/io_result_copy_read/windows"

///|
fn IoResult::for_file_read(
  buf : FixedArray[Byte],
  offset~ : Int,
  len~ : Int,
  position~ : Int64,
) -> IoResult {
  IoResult(IoResultHandle::for_file_read(len~, position~), copy_output=handle => {
    handle.copy_read(buf, offset~, len~)
  })
}

///|
#unsafe_skip_stub_check
#borrow(buf)
fn IoResultHandle::for_file_write(
  buf : Bytes,
  offset~ : Int,
  len~ : Int,
  position~ : Int64,
) -> IoResultHandle = "moonbitlang/async" "io/make_file_write_io_result/windows"

///|
fn IoResult::for_file_write(
  buf : Bytes,
  offset~ : Int,
  len~ : Int,
  position~ : Int64,
) -> IoResult {
  IoResult(IoResultHandle::for_file_write(buf, offset~, len~, position~))
}

///|
#unsafe_skip_stub_check
fn IoResultHandle::for_socket_read(len~ : Int, flags~ : Int) -> IoResultHandle = "moonbitlang/async" "io/make_socket_read_io_result/windows"

///|
fn IoResult::for_socket_read(
  buf : FixedArray[Byte],
  offset~ : Int,
  len~ : Int,
  flags~ : Int,
) -> IoResult {
  IoResult(IoResultHandle::for_socket_read(len~, flags~), copy_output=handle => {
    handle.copy_read(buf, offset~, len~)
  })
}

///|
#unsafe_skip_stub_check
#borrow(buf)
fn IoResultHandle::for_socket_write(
  buf : Bytes,
  offset~ : Int,
  len~ : Int,
  flags~ : Int,
) -> IoResultHandle = "moonbitlang/async" "io/make_socket_write_io_result/windows"

///|
fn IoResult::for_socket_write(
  buf : Bytes,
  offset~ : Int,
  len~ : Int,
  flags~ : Int,
) -> IoResult {
  IoResult(IoResultHandle::for_socket_write(buf, offset~, len~, flags~))
}

///|
#unsafe_skip_stub_check
#borrow(addr)
fn IoResultHandle::for_socket_with_addr_read(
  len~ : Int,
  flags~ : Int,
  addr~ : Bytes,
  addr_len? : Int = addr.length(),
) -> IoResultHandle = "moonbitlang/async" "io/make_socket_with_addr_read_io_result/windows"

///|
#unsafe_skip_stub_check
#borrow(dst, addr)
fn IoResultHandle::copy_read_with_addr(
  result : IoResultHandle,
  dst : FixedArray[Byte],
  offset~ : Int,
  len~ : Int,
  addr~ : Bytes,
  addr_len? : Int = addr.length(),
) -> Unit = "moonbitlang/async" "io/io_result_copy_read_with_addr/windows"

///|
fn IoResult::for_socket_with_addr_read(
  buf : FixedArray[Byte],
  offset~ : Int,
  len~ : Int,
  flags~ : Int,
  addr~ : Bytes,
) -> IoResult {
  IoResult(IoResultHandle::for_socket_with_addr_read(len~, flags~, addr~), copy_output=handle => {
    handle.copy_read_with_addr(buf, offset~, len~, addr~)
  })
}

///|
#unsafe_skip_stub_check
#borrow(buf, addr)
fn IoResultHandle::for_socket_with_addr_write(
  buf : Bytes,
  offset~ : Int,
  len~ : Int,
  flags~ : Int,
  addr~ : Bytes,
  addr_len? : Int = addr.length(),
) -> IoResultHandle = "moonbitlang/async" "io/make_socket_with_addr_write_io_result/windows"

///|
fn IoResult::for_socket_with_addr_write(
  buf : Bytes,
  offset~ : Int,
  len~ : Int,
  flags~ : Int,
  addr~ : Bytes,
) -> IoResult {
  IoResult(
    IoResultHandle::for_socket_with_addr_write(
      buf,
      offset~,
      len~,
      flags~,
      addr~,
    ),
  )
}

///|
#unsafe_skip_stub_check
#borrow(addr)
fn IoResultHandle::for_connect(
  addr : Bytes,
  addr_len? : Int = addr.length(),
) -> IoResultHandle = "moonbitlang/async" "io/make_connect_io_result/windows"

///|
fn IoResult::for_connect(addr : Bytes) -> IoResult {
  IoResult(IoResultHandle::for_connect(addr))
}

///|
#unsafe_skip_stub_check
fn IoResultHandle::for_accept(addr_len : Int) -> IoResultHandle = "moonbitlang/async" "io/make_accept_io_result/windows"

///|
fn IoResult::for_accept(addr_len : Int) -> IoResult {
  IoResult(IoResultHandle::for_accept(addr_len))
}

///|
#unsafe_skip_stub_check
#borrow(dst)
fn IoResultHandle::get_accept_peer_addr(
  self : IoResultHandle,
  dst : Bytes,
  dst_len? : Int = dst.length(),
) -> Unit = "moonbitlang/async" "io/get_accept_peer_addr/windows"

///|
fn IoResult::get_accept_peer_addr(self : IoResult, dst : Bytes) -> Unit {
  self.handle.get_accept_peer_addr(dst)
}

///|
#unsafe_skip_stub_check
fn IoResultHandle::free(self : IoResultHandle) -> Unit = "moonbitlang/async" "io/free_io_result/windows"

///|
fn IoResult::free(self : IoResult) -> Unit {
  self.handle.free()
}

///|
#unsafe_skip_stub_check
fn IoResultHandle::event(self : IoResultHandle) -> Int = "moonbitlang/async" "io/io_result_get_event/windows"

///|
#unsafe_skip_stub_check
fn IoResultHandle::cancel_ffi(
  self : IoResultHandle,
  handle : @fd_util.Fd,
) -> Int = "moonbitlang/async" "io/cancel_io_result/windows"

///|
fn IoResult::cancel(
  self : IoResult,
  handle : @fd_util.Fd,
  context~ : String,
) -> CancellationStatus raise {
  let ret = self.handle.cancel_ffi(handle)
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
fn IoResultHandle::status_ffi(
  result : IoResultHandle,
  handle : @fd_util.Fd,
) -> Int = "moonbitlang/async" "io/io_result_get_status/windows"

///|
fn IoResult::status(
  result : IoResult,
  handle : @fd_util.Fd,
  context~ : String,
) -> Int raise {
  let n = result.handle.status_ffi(handle)
  if n < 0 {
    if errno_is_cancelled(@os_error.get_errno()) {
      raise @coroutine.Cancelled
    } else {
      @os_error.check_errno(context)
    }
  }
  if result.copy_output is Some(copy_output) {
    copy_output(result.handle)
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
fn read_io_result_ffi(fd : @fd_util.Fd, result : IoResultHandle) -> Int = "moonbitlang/async" "io/read/windows"

///|
fn read_windows_ffi(fd : @fd_util.Fd, result : IoResult) -> Int {
  read_io_result_ffi(fd, result.handle)
}

///|
#unsafe_skip_stub_check
fn errno_is_read_eof(errno : Int) -> Bool = "moonbitlang/async" "io/errno_is_read_EOF/windows"

///|
async fn IoHandle::generic_read_windows(
  handle : IoHandle,
  result : IoResult,
  context~ : String,
) -> Int {
  let n = read_windows_ffi(handle.fd, result)
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
async fn IoHandle::read_via_event_bus_windows(
  handle : IoHandle,
  buf : FixedArray[Byte],
  offset~ : Int,
  len~ : Int,
  context~ : String,
) -> Int {
  let result = match handle.kind {
    Regular => panic()
    Socket => IoResult::for_socket_read(buf, offset~, len~, flags=0)
    _ => IoResult::for_file_read(buf, offset~, len~, position=0)
  }
  defer result.free()
  handle.generic_read_windows(result, context~)
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
fn write_io_result_ffi(fd : @fd_util.Fd, result : IoResultHandle) -> Int = "moonbitlang/async" "io/write/windows"

///|
fn write_windows_ffi(fd : @fd_util.Fd, result : IoResult) -> Int {
  write_io_result_ffi(fd, result.handle)
}

///|
async fn IoHandle::generic_write_windows(
  handle : IoHandle,
  result : IoResult,
  context~ : String,
) -> Int {
  let n = write_windows_ffi(handle.fd, result)
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
