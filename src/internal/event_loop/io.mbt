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
pub struct IoHandle {
  priv mut fd : @fd_util.Fd
  priv kind : @fd_util.FileKind
  /// - `is_async=true`: support native async operations through the event bus.
  ///   This usually means the fd is non blocking (Unix) or overlapped (Windows)
  /// - `is_async=false`: all operations are blocking and go through the thread pool
  priv is_async : Bool
  priv mut read : IoStatus
  /// The current offset for reading.
  /// A negative value indicates that the underlying object does not support random access.
  ///
  /// We manually maintain `read_offset`,
  /// because the semantic of native file pointer is undesirable:
  ///
  /// - On Unix-like systems, read/write share the same file pointer.
  /// - On Windows, random access read/write will change the file pointer for synchronous handle.
  mut read_offset : Int64
  priv mut write : IoStatus
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
///
/// - `is_async` indicates whether the file descriptor support async operations.
///   On Unix systems, if `is_async=true`, the file descriptor will be set to non-blocking mode,
///   On Windows, the file descriptor must be created in overlapped mode.
///
/// - `read_only` indicates whether the handle has the concept of writing.
///   By default, `IoHandle::from_fd` will register both read/write events for the file descriptor,
///   If `read_only=true`, only read event will be registered.
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
  let job = Job::read(handle.fd, buf, offset, len, position=handle.read_offset)
  defer job.free()
  let cancel = if platform is Windows || handle.kind.can_poll() {
    Some(job_id => evloop.cancel_job_in_worker(job_id, context~))
  } else {
    None
  }
  perform_job_in_worker(job, context~, cancel?)
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
    /// The implementation of `read_via_event_bus` is platform dependent,
    /// and is located in `io_unix.mbt`, `io_windows.mbt` etc.
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
    /// The implementation of `write_via_event_bus` is platform dependent,
    /// and is located in `io_unix.mbt`, `io_windows.mbt` etc.
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
  let job = Job::read(handle.fd, buf, offset, len, position~)
  defer job.free()
  let cancel = if platform is Windows {
    Some(job_id => evloop.cancel_job_in_worker(job_id, context~))
  } else {
    None
  }
  perform_job_in_worker(job, context~, cancel?)
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
