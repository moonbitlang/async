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
extern "C" fn IoResult::for_file_ffi(
  job_id : Int,
  buf : Bytes,
  offset~ : Int,
  len~ : Int,
  position~ : Int64,
) -> IoResult = "moonbitlang_async_make_file_io_result"

///|
#cfg(platform="windows")
fn IoResult::for_file(
  buf : Bytes,
  offset~ : Int,
  len~ : Int,
  position~ : Int64,
) -> IoResult {
  guard curr_loop.val is Some(evloop)
  IoResult::for_file_ffi(
    evloop.backend.next_operation_id(),
    buf,
    offset~,
    len~,
    position~,
  )
}

///|
#cfg(platform="windows")
#owned(buf)
extern "C" fn IoResult::for_socket_ffi(
  job_id : Int,
  buf : Bytes,
  offset~ : Int,
  len~ : Int,
  flags~ : Int,
) -> IoResult = "moonbitlang_async_make_socket_io_result"

///|
#cfg(platform="windows")
fn IoResult::for_socket(
  buf : Bytes,
  offset~ : Int,
  len~ : Int,
  flags~ : Int,
) -> IoResult {
  guard curr_loop.val is Some(evloop)
  IoResult::for_socket_ffi(
    evloop.backend.next_operation_id(),
    buf,
    offset~,
    len~,
    flags~,
  )
}

///|
#cfg(platform="windows")
#owned(buf, addr)
extern "C" fn IoResult::for_socket_with_addr_ffi(
  job_id : Int,
  buf : Bytes,
  offset~ : Int,
  len~ : Int,
  flags~ : Int,
  addr~ : Bytes,
) -> IoResult = "moonbitlang_async_make_socket_with_addr_io_result"

///|
#cfg(platform="windows")
fn IoResult::for_socket_with_addr(
  buf : Bytes,
  offset~ : Int,
  len~ : Int,
  flags~ : Int,
  addr~ : Bytes,
) -> IoResult {
  guard curr_loop.val is Some(evloop)
  IoResult::for_socket_with_addr_ffi(
    evloop.backend.next_operation_id(),
    buf,
    offset~,
    len~,
    flags~,
    addr~,
  )
}

///|
#cfg(platform="windows")
#owned(addr)
extern "C" fn IoResult::for_connect_ffi(job_id : Int, addr : Bytes) -> IoResult = "moonbitlang_async_make_connect_io_result"

///|
#cfg(platform="windows")
fn IoResult::for_connect(addr : Bytes) -> IoResult {
  guard curr_loop.val is Some(evloop)
  IoResult::for_connect_ffi(evloop.backend.next_operation_id(), addr)
}

///|
#cfg(platform="windows")
extern "C" fn IoResult::for_accept_ffi(job_id : Int) -> IoResult = "moonbitlang_async_make_accept_io_result"

///|
#cfg(platform="windows")
fn IoResult::for_accept() -> IoResult {
  guard curr_loop.val is Some(evloop)
  IoResult::for_accept_ffi(evloop.backend.next_operation_id())
}

///|
#cfg(platform="windows")
#owned(buf)
extern "C" fn IoResult::for_read_dir_changes_ffi(
  job_id : Int,
  buf : Bytes,
  len~ : Int,
) -> IoResult = "moonbitlang_async_make_read_dir_changes_io_result"

///|
#cfg(platform="windows")
fn IoResult::for_read_dir_changes(buf : Bytes, len~ : Int) -> IoResult {
  guard curr_loop.val is Some(evloop)
  IoResult::for_read_dir_changes_ffi(
    evloop.backend.next_operation_id(),
    buf,
    len~,
  )
}

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
struct IoHandle {
  mut fd : @fd_util.Fd
  kind : @fd_util.FileKind
  is_async : Bool
  mut reading : Bool
  mut read_offset : Int64
  mut writing : Bool
  mut write_offset : Int64
}

///|
/// Create a IO handle from a raw file descriptor.
/// The ownership of the file descriptor would be transferred to this function,
/// so the caller must not close the file descriptor manually in any circumstances.
#cfg(platform="windows")
pub fn IoHandle::from_fd(
  fd : @fd_util.Fd,
  kind~ : @fd_util.FileKind,
  is_async? : Bool = true,
) -> IoHandle raise {
  let context = "@event_loop.IoHandle::from_fd()"
  guard curr_loop.val is Some(evloop)
  guard evloop.backend.fds.get(fd) is None
  if is_async {
    evloop.backend.poll.register(fd) catch {
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
    reading: false,
    read_offset: 0,
    writing: false,
    write_offset: 0,
  }
  evloop.backend.fds[fd] = handle
  handle
}

///|
#cfg(platform="windows")
pub fn IoHandle::detach_from_event_loop(handle : IoHandle) -> Unit {
  guard curr_loop.val is Some(evloop)
  guard @fd_util.fd_is_valid(handle.fd) else { return }
  evloop.backend.fds.remove(handle.fd)
}

///|
#cfg(platform="windows")
async fn EventLoop::wait_for_io_result(
  evloop : EventLoop,
  io_result : IoResult,
  handle : @fd_util.Fd,
  context~ : String,
) -> Unit {
  let operation_id = io_result.job_id()
  let (subscription_id, operation) = evloop.subscribe_backend_operation(
    subscription_id => {
      evloop.backend.completion_operation(subscription_id, operation_id)
    },
    Wake(@coroutine.current_coroutine()),
  )
  evloop.wait_for_submitted_operation(subscription_id, operation, cancel=_ => {
    io_result.cancel(handle, context~)
  })
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
  guard curr_loop.val is Some(evloop)
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
    evloop.wait_for_io_result(result, handle.fd, context~)
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
pub async fn IoHandle::read(
  handle : IoHandle,
  buf : FixedArray[Byte],
  offset~ : Int,
  len~ : Int,
  context~ : String,
) -> Int {
  @coroutine.check_cancellation()
  guard !handle.reading
  handle.reading = true
  defer {
    handle.reading = false
  }
  guard curr_loop.val is Some(evloop)
  if !handle.is_async {
    let spec = OperationSpec::read(
      handle.fd,
      buf,
      offset,
      len,
      position=handle.read_offset,
    )
    let job = perform_operation(spec, context~, cancel=job => {
      evloop.backend.cancel_operation(job, context~)
    }) catch {
      @os_error.OSError(errno, ..) if errno_is_read_eof(errno) => return 0
      err => raise err
    }
    defer job.free()
    let n = job.ret()
    handle.read_offset += n.to_int64()
    return n
  }
  let result = match handle.kind {
    Regular => panic()
    Socket =>
      IoResult::for_socket(
        buf.unsafe_reinterpret_as_bytes(),
        offset~,
        len~,
        flags=0,
      )
    _ =>
      IoResult::for_file(
        buf.unsafe_reinterpret_as_bytes(),
        offset~,
        len~,
        position=0,
      )
  }
  defer result.free()
  let n = handle.generic_read(result, context~)
  handle.read_offset += n.to_int64()
  n
}

///|
#cfg(platform="windows")
pub async fn IoHandle::read_at(
  handle : IoHandle,
  buf : FixedArray[Byte],
  offset~ : Int,
  len~ : Int,
  position~ : Int64,
  context~ : String,
) -> Int {
  @coroutine.check_cancellation()
  guard curr_loop.val is Some(evloop)
  guard handle.kind is Regular
  let job = perform_operation(
    OperationSpec::read(handle.fd, buf, offset, len, position~),
    context~,
    cancel=job => evloop.backend.cancel_operation(job, context~),
  ) catch {
    @os_error.OSError(errno, ..) if errno_is_read_eof(errno) => return 0
    err => raise err
  }
  defer job.free()
  job.ret()
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
  guard curr_loop.val is Some(evloop)
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
    evloop.wait_for_io_result(result, handle.fd, context~)
    result.status(handle.fd, context~)
  } else {
    @os_error.check_errno(context)
    panic()
  }
}

///|
#cfg(platform="windows")
pub async fn IoHandle::write(
  handle : IoHandle,
  buf : Bytes,
  offset~ : Int,
  len~ : Int,
  context~ : String,
) -> Int {
  @coroutine.check_cancellation()
  guard !handle.writing
  handle.writing = true
  defer {
    handle.writing = false
  }
  guard curr_loop.val is Some(evloop)
  if !handle.is_async {
    let job = perform_operation(
      OperationSpec::write(
        handle.fd,
        buf,
        offset,
        len,
        position=handle.write_offset,
      ),
      context~,
      cancel=job => evloop.backend.cancel_operation(job, context~),
    )
    defer job.free()
    let n = job.ret()
    handle.write_offset += n.to_int64()
    return n
  }
  let result = match handle.kind {
    Regular => panic()
    Socket => IoResult::for_socket(buf, offset~, len~, flags=0)
    _ => IoResult::for_file(buf, offset~, len~, position=0)
  }
  defer result.free()
  let n = handle.generic_write(result, context~)
  handle.write_offset += n.to_int64()
  n
}

///|
#cfg(platform="windows")
pub async fn IoHandle::write_at(
  handle : IoHandle,
  buf : Bytes,
  offset~ : Int,
  len~ : Int,
  position~ : Int64,
  context~ : String,
) -> Unit {
  @coroutine.check_cancellation()
  guard curr_loop.val is Some(evloop)
  guard handle.kind is Regular
  let job = perform_operation(
    OperationSpec::write(handle.fd, buf, offset, len, position~),
    context~,
    cancel=job => evloop.backend.cancel_operation(job, context~),
  )
  defer job.free()
}
