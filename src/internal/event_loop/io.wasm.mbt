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
priv enum IoStatus {
  Idle
  // a pending read/write operation is already submitted to thread pool
  Submitted
  // waiting for read/write readiness or completion from the event bus
  Waiting(@coroutine.Coroutine)
}

///|
/// A managed file descriptor/`HANDLE`,
/// capable of performing async IO operations.
struct IoHandle {
  mut fd : @fd_util.Fd
  kind : @fd_util.FileKind
  /// - `is_async=true`: support native async operations through the event bus.
  ///   This usually means the fd is non blocking (Unix) or overlapped (Windows)
  /// - `is_async=false`: all operations are blocking and go through the thread pool
  is_async : Bool
  mut read : IoStatus
  /// The current offset for reading.
  /// A negative value indicates that the underlying object does not support random access.
  mut read_offset : Int64
  mut write : IoStatus
  /// Similar to `read_offset`, but for the write end of the object.
  mut write_offset : Int64
}

///|
pub fn IoHandle::fd(handle : IoHandle) -> @fd_util.Fd {
  handle.fd
}

///|
pub fn IoHandle::kind(handle : IoHandle) -> @fd_util.FileKind {
  handle.kind
}

///|
/// Detach a file descriptor from the event loop,
/// but does not close the file descriptor itself.
/// The underlying file descriptor is returned.
pub fn IoHandle::detach_from_event_loop(handle : IoHandle) -> Unit {
  guard curr_loop.val is Some(evloop)
  guard @fd_util.fd_is_valid(handle.fd) else { return }
  evloop.fds.remove(handle.fd)
}

///|
/// Close a file descriptor and detach it from the event loop.
/// This function is idempotent: it is safe to call `.close()` multiple times.
pub fn IoHandle::close(handle : IoHandle) -> Unit {
  handle.detach_from_event_loop()
  if @fd_util.fd_is_valid(handle.fd) {
    @fd_util.close(handle.fd, kind=handle.kind, context="") catch {
      _ => ()
    }
  }
  handle.fd = @fd_util.invalid_fd
}

///|
/// Create a IO handle from a raw file descriptor, and register the file descriptor to the event loop.
/// The ownership of the file descriptor would be transferred to this function,
/// so the caller must not close the file descriptor manually in any circumstances.
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
    evloop.bus.register(fd, read_only~) catch {
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
    read_offset: if kind is Regular {
      0
    } else {
      -1
    },
    write: Idle,
    write_offset: if kind is Regular {
      0
    } else {
      -1
    },
  }
  evloop.fds[fd] = handle
  handle
}

///|
/// Perform a read operation on the IO handle via the thread pool.
/// Used for handling objects that do not support native async reading.
async fn IoHandle::read_via_worker(
  handle : IoHandle,
  buf : FixedArray[Byte],
  offset~ : Int,
  len~ : Int,
  context~ : String,
) -> Int {
  guard curr_loop.val is Some(evloop)
  guard handle.read is Idle
  handle.read = Submitted
  defer {
    handle.read = Idle
  }
  let job = Job::read(handle.fd, len, position=handle.read_offset)
  defer job.free()
  let cancel = if platform is Windows || handle.kind.can_poll() {
    Some(job_id => evloop.cancel_job_in_worker(job_id, context~))
  } else {
    None
  }
  let ret = perform_job_in_worker(job, context~, cancel?)
  job.get_read_result(buf, offset, len)
  ret
}

///|
pub async fn IoHandle::read(
  handle : IoHandle,
  buf : FixedArray[Byte],
  offset~ : Int,
  len~ : Int,
  context~ : String,
) -> Int {
  @coroutine.check_cancellation()
  let n = if handle.is_async {
    /// The implementation of `read_via_event_bus` is platform dependent.
    /// Wasm dispatches at runtime because the same artifact may run on any host OS.
    handle.read_via_event_bus(buf, offset~, len~, context~)
  } else {
    handle.read_via_worker(buf, offset~, len~, context~)
  }
  if handle.read_offset >= 0 {
    handle.read_offset += n.to_int64()
  }
  n
}

///|
/// Perform a write operation on the IO handle via the thread pool.
/// Used for handling objects that do not support native async writing.
async fn IoHandle::write_via_worker(
  handle : IoHandle,
  buf : Bytes,
  offset~ : Int,
  len~ : Int,
  context~ : String,
) -> Int {
  guard curr_loop.val is Some(evloop)
  guard handle.write is Idle
  handle.write = Submitted
  defer {
    handle.write = Idle
  }
  let job = Job::write(
    handle.fd,
    buf,
    offset,
    len,
    position=handle.write_offset,
  )
  defer job.free()
  let cancel = if platform is Windows || handle.kind.can_poll() {
    Some(job_id => evloop.cancel_job_in_worker(job_id, context~))
  } else {
    None
  }
  perform_job_in_worker(job, context~, cancel?)
}

///|
pub async fn IoHandle::write(
  handle : IoHandle,
  buf : Bytes,
  offset~ : Int,
  len~ : Int,
  context~ : String,
) -> Int {
  @coroutine.check_cancellation()
  let n = if handle.is_async {
    /// The implementation of `write_via_event_bus` is platform dependent.
    /// Wasm dispatches at runtime because the same artifact may run on any host OS.
    handle.write_via_event_bus(buf, offset~, len~, context~)
  } else {
    handle.write_via_worker(buf, offset~, len~, context~)
  }
  if handle.write_offset >= 0 {
    handle.write_offset += n.to_int64()
  }
  n
}

///|
/// Perform a random access read on the IO handle.
/// Since only regular files support random access IO,
/// `read_at` is always dispatched to the thread pool.
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
  guard !handle.is_async
  let job = Job::read(handle.fd, len, position~)
  defer job.free()
  let cancel = if platform is Windows {
    Some(job_id => evloop.cancel_job_in_worker(job_id, context~))
  } else {
    None
  }
  let ret = perform_job_in_worker(job, context~, cancel?)
  job.get_read_result(buf, offset, len)
  ret
}

///|
/// Perform a random access write on the IO handle.
/// Since only regular files support random access IO,
/// `write_at` is always dispatched to the thread pool.
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
  guard !handle.is_async
  guard handle.write_offset >= 0 else {
    raise Failure::Failure(
      "`write_at` is not supported on non-regular file or file opened in append mode",
    )
  }
  let job = Job::write(handle.fd, buf, offset, len, position~)
  defer job.free()
  let cancel = if platform is Windows {
    Some(job_id => evloop.cancel_job_in_worker(job_id, context~))
  } else {
    None
  }
  ignore(perform_job_in_worker(job, context~, cancel?))
}

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
#borrow(buf)
fn IoResult::for_file(
  events : Int,
  buf : Bytes,
  offset~ : Int,
  len~ : Int,
  position~ : Int64,
) -> IoResult = "moonbitlang/async" "io/make_file_io_result/windows"

///|
#unsafe_skip_stub_check
#borrow(buf)
fn IoResult::for_socket(
  events : Int,
  buf : Bytes,
  offset~ : Int,
  len~ : Int,
  flags~ : Int,
) -> IoResult = "moonbitlang/async" "io/make_socket_io_result/windows"

///|
#unsafe_skip_stub_check
#borrow(buf, addr)
fn IoResult::for_socket_with_addr(
  events : Int,
  buf : Bytes,
  offset~ : Int,
  len~ : Int,
  flags~ : Int,
  addr~ : Bytes,
  addr_len? : Int = addr.length(),
) -> IoResult = "moonbitlang/async" "io/make_socket_with_addr_io_result/windows"

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
async fn IoHandle::generic_read_windows(
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
async fn IoHandle::read_via_event_bus_windows(
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
    Socket => IoResult::for_socket(WriteEvent, buf, offset~, len~, flags=0)
    _ => IoResult::for_file(WriteEvent, buf, offset~, len~, position=0)
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
