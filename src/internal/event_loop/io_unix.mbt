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
#cfg(not(platform="windows"))
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
#cfg(not(platform="windows"))
async fn IoHandle::wait_write(handle : IoHandle) -> Unit {
  guard @fd_util.fd_is_valid(handle.fd) else {
    abort("file descriptor already closed")
  }
  guard handle.write is Idle
  let coro = @coroutine.current_coroutine()
  handle.write = Waiting(coro)
  defer {
    handle.write = Idle
  }
  @coroutine.suspend()
}

///|
#cfg(not(platform="windows"))
#borrow(buf)
extern "C" fn read_ffi(
  fd : @fd_util.Fd,
  buf : FixedArray[Byte],
  offset~ : Int,
  len~ : Int,
) -> Int = "moonbitlang_async_read"

///|
#cfg(not(platform="windows"))
async fn IoHandle::read_via_event_bus(
  handle : IoHandle,
  buf : FixedArray[Byte],
  offset~ : Int,
  len~ : Int,
  context~ : String,
) -> Int {
  let ret = read_ffi(handle.fd, buf, offset~, len~)
  if ret >= 0 {
    // The `pause` here prevent a busy read loop from exhausting the whole program
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
#cfg(not(platform="windows"))
#borrow(buf)
extern "C" fn write_ffi(
  fd : @fd_util.Fd,
  buf : Bytes,
  offset~ : Int,
  len~ : Int,
) -> Int = "moonbitlang_async_write"

///|
#cfg(not(platform="windows"))
async fn IoHandle::write_via_event_bus(
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
