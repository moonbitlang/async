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
pub async fn IoHandle::wait_read(handle : IoHandle, loc~ : SourceLoc) -> Unit {
  guard curr_loop.val is Some(evloop)
  guard @fd_util.fd_is_valid(handle.fd) else {
    abort("file descriptor already closed")
  }
  guard handle.read is Idle
  handle.read = Waiting(@coroutine.current_coroutine())
  defer {
    handle.read = Idle
  }
  evloop.suspend(loc~)
}

///|
#cfg(not(platform="windows"))
async fn IoHandle::wait_write(handle : IoHandle, loc~ : SourceLoc) -> Unit {
  guard curr_loop.val is Some(evloop)
  guard @fd_util.fd_is_valid(handle.fd) else {
    abort("file descriptor already closed")
  }
  guard handle.write is Idle
  let coro = @coroutine.current_coroutine()
  handle.write = Waiting(coro)
  defer {
    handle.write = Idle
  }
  evloop.suspend(loc~)
}

///|
#cfg(all(target="native", not(platform="windows")))
#borrow(buf)
extern "C" fn read_unix_ffi(
  fd : @fd_util.Fd,
  buf : FixedArray[Byte],
  offset~ : Int,
  len~ : Int,
) -> Int = "moonbitlang_async_read"

///|
#cfg(target="wasm")
#unsafe_skip_stub_check
#borrow(buf)
fn read_unix_ffi(
  fd : @fd_util.Fd,
  buf : FixedArray[Byte],
  offset~ : Int,
  len~ : Int,
) -> Int = "moonbitlang/async" "io/read/unix"

///|
#cfg(not(platform="windows"))
async fn IoHandle::read_via_event_bus_unix(
  handle : IoHandle,
  buf : FixedArray[Byte],
  offset~ : Int,
  len~ : Int,
  context~ : String,
  loc~ : SourceLoc,
) -> Int {
  let ret = read_unix_ffi(handle.fd, buf, offset~, len~)
  if ret >= 0 {
    // The `pause` here prevent a busy read loop from exhausting the whole program
    // and give chance for other tasks to execute.
    @coroutine.protect_from_cancel(
      () => @coroutine.pause(loc~),
      resume_on_cancel=true,
    )
    return ret
  }
  let ret = if @os_error.is_nonblocking_io_error() {
    handle.wait_read(loc~)
    read_unix_ffi(handle.fd, buf, offset~, len~)
  } else {
    ret
  }
  if ret < 0 {
    @os_error.check_errno(context)
  }
  ret
}

///|
#cfg(all(target="native", not(platform="windows")))
async fn IoHandle::read_via_event_bus(
  handle : IoHandle,
  buf : FixedArray[Byte],
  offset~ : Int,
  len~ : Int,
  context~ : String,
  loc~ : SourceLoc,
) -> Int {
  handle.read_via_event_bus_unix(buf, offset~, len~, context~, loc~)
}

///|
#cfg(all(target="native", not(platform="windows")))
#borrow(buf)
extern "C" fn write_unix_ffi(
  fd : @fd_util.Fd,
  buf : Bytes,
  offset~ : Int,
  len~ : Int,
) -> Int = "moonbitlang_async_write"

///|
#cfg(target="wasm")
#unsafe_skip_stub_check
#borrow(buf)
fn write_unix_ffi(
  fd : @fd_util.Fd,
  buf : Bytes,
  offset~ : Int,
  len~ : Int,
) -> Int = "moonbitlang/async" "io/write/unix"

///|
#cfg(not(platform="windows"))
async fn IoHandle::write_via_event_bus_unix(
  handle : IoHandle,
  buf : Bytes,
  offset~ : Int,
  len~ : Int,
  context~ : String,
  loc~ : SourceLoc,
) -> Int {
  let ret = write_unix_ffi(handle.fd, buf, offset~, len~)
  if ret >= 0 {
    // The `pause` here prevent a busy write loop from exhausting the whole program,
    // and give chance for other tasks to execute.
    @coroutine.protect_from_cancel(
      () => @coroutine.pause(loc~),
      resume_on_cancel=true,
    )
    return ret
  }
  let ret = if @os_error.is_nonblocking_io_error() {
    handle.wait_write(loc~)
    write_unix_ffi(handle.fd, buf, offset~, len~)
  } else {
    ret
  }
  if ret < 0 {
    @os_error.check_errno(context)
  }
  ret
}

///|
#cfg(all(target="native", not(platform="windows")))
async fn IoHandle::write_via_event_bus(
  handle : IoHandle,
  buf : Bytes,
  offset~ : Int,
  len~ : Int,
  context~ : String,
  loc~ : SourceLoc,
) -> Int {
  handle.write_via_event_bus_unix(buf, offset~, len~, context~, loc~)
}
