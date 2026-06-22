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
  // a pending read/write operation is already submitted to the OS or thread pool
  Submitted
  // waiting for read/write readiness
  Waiting(@coroutine.Coroutine)
}

///|
#warnings("-unused_field")
struct IoHandle {
  mut fd : @fd_util.Fd
  kind : @fd_util.FileKind
  is_async : Bool
  mut read : IoStatus
  mut read_offset : Int64
  mut write : IoStatus
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
  let job = Job::write(handle.fd, buf, offset, len, position~)
  defer job.free()
  let cancel = if platform is Windows {
    Some(job_id => evloop.cancel_job_in_worker(job_id, context~))
  } else {
    None
  }
  ignore(perform_job_in_worker(job, context~, cancel?))
}
