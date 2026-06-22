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
/// Create a IO handle from a raw file descriptor.
/// The ownership of the file descriptor would be transferred to this function,
/// so the caller must not close the file descriptor manually in any circumstances.
#cfg(not(platform="windows"))
pub fn IoHandle::from_fd(
  fd : @fd_util.Fd,
  kind~ : @fd_util.FileKind,
  is_async? : Bool = true,
  read_only? : Bool = false,
) -> IoHandle raise {
  let context = "@event_loop.IoHandle::from_fd()"
  guard curr_loop.val is Some(evloop)
  guard evloop.fds.get(fd) is None
  if is_async {
    try {
      if !(kind is Unknown) {
        @fd_util.set_nonblocking(fd, context~)
      }
      evloop.bus.register(fd, read_only~)
    } catch {
      err => {
        @fd_util.close(fd, kind~, context~)
        raise err
      }
    }
  }
  let handle = {
    fd,
    kind,
    is_async,
    read: Idle,
    read_offset: 0,
    write: Idle,
    write_offset: 0,
  }
  evloop.fds[fd] = handle
  handle
}

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
pub async fn IoHandle::read(
  handle : IoHandle,
  buf : FixedArray[Byte],
  offset~ : Int,
  len~ : Int,
  context~ : String,
) -> Int {
  if handle.is_async {
    @coroutine.check_cancellation()
    let ret = read_ffi(handle.fd, buf, offset~, len~)
    if ret >= 0 {
      @coroutine.pause()
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
  } else {
    handle.read = Submitted
    defer {
      handle.read = Idle
    }
    let cancel = if handle.kind.can_poll() {
      guard curr_loop.val is Some(evloop)
      Some(job_id => evloop.cancel_job_in_worker(job_id, context~))
    } else {
      None
    }
    let job = Job::read(handle.fd, buf, offset, len, position=-1)
    defer job.free()
    perform_job_in_worker(job, context~, cancel?)
  }
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
pub async fn IoHandle::write(
  handle : IoHandle,
  buf : Bytes,
  offset~ : Int,
  len~ : Int,
  context~ : String,
) -> Int {
  if handle.is_async {
    @coroutine.check_cancellation()
    let ret = write_ffi(handle.fd, buf, offset~, len~)
    if ret >= 0 {
      @coroutine.pause()
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
  } else {
    handle.write = Submitted
    defer {
      handle.write = Idle
    }
    let cancel = if handle.kind.can_poll() {
      guard curr_loop.val is Some(evloop)
      Some(job_id => evloop.cancel_job_in_worker(job_id, context~))
    } else {
      None
    }
    let job = Job::write(handle.fd, buf, offset, len, position=-1)
    defer job.free()
    perform_job_in_worker(job, context~, cancel?)
  }
}
