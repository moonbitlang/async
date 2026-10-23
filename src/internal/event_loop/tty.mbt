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
/// A handle on a terminal, see `@tty` for the user facing API.
/// It owns the input descriptor, the saved terminal state and the resize flag.
/// The output descriptor is returned by `open` and managed by the caller.
///
/// The handle is allocated by C and lives for the rest of the process:
/// there is one terminal per program and it is never closed.
#external
pub type Tty

///|
#owned(path)
#borrow(out_fd)
extern "C" fn Tty::open_ffi(
  path : Bytes,
  out_fd : FixedArray[@fd_util.Fd],
) -> Tty = "moonbitlang_async_tty_open"

///|
/// Open the terminal at `path` (normally `/dev/tty`).
/// Return the handle together with a second descriptor for the same terminal,
/// intended to be wrapped in an `IoHandle` for output.
///
/// On Unix, this also blocks `SIGWINCH` in the calling thread:
/// resize is observed through a `signalfd`/`kqueue` by `read`.
pub fn Tty::open(path : Bytes, context~ : String) -> (Tty, @fd_util.Fd) raise {
  let out_fd = FixedArray::make(1, @fd_util.invalid_fd)
  // On failure the C side returns `NULL`, which must never be used,
  // and reports the failure through `out_fd`.
  let handle = Tty::open_ffi(path, out_fd)
  if !@fd_util.fd_is_valid(out_fd[0]) {
    @os_error.check_errno(context)
  }
  (handle, out_fd[0])
}

///|
extern "C" fn Tty::enter_raw_ffi(self : Tty) -> Int32 = "moonbitlang_async_tty_enter_raw"

///|
/// Put the terminal into raw mode, saving the current state.
/// No-op if a saved state already exists.
pub fn Tty::enter_raw(self : Tty, context~ : String) -> Unit raise {
  if self.enter_raw_ffi() < 0 {
    @os_error.check_errno(context)
  }
}

///|
extern "C" fn Tty::leave_raw_ffi(self : Tty) -> Int32 = "moonbitlang_async_tty_leave_raw"

///|
/// Restore the terminal state saved by `enter_raw` and forget it.
/// No-op if there is no saved state.
pub fn Tty::leave_raw(self : Tty, context~ : String) -> Unit raise {
  if self.leave_raw_ffi() < 0 {
    @os_error.check_errno(context)
  }
}

///|
extern "C" fn Tty::size_ffi(self : Tty) -> Int64 = "moonbitlang_async_tty_size"

///|
/// The size of the terminal window as `(rows, cols)`.
pub fn Tty::size(self : Tty, context~ : String) -> (Int32, Int32) raise {
  let packed = self.size_ffi()
  if packed < 0 {
    @os_error.check_errno(context)
  }
  ((packed >> 32).to_int(), (packed & 0xFFFF).to_int())
}

///|
extern "C" fn Tty::take_resize_event_ffi(self : Tty) -> Int32 = "moonbitlang_async_tty_take_resize_event"

///|
/// Whether a resize was observed by a read since the last call, clearing the flag.
/// Only meaningful when no read is in progress.
pub fn Tty::take_resize_event(self : Tty) -> Bool {
  self.take_resize_event_ffi() != 0
}

///|
#owned(buf)
extern "C" fn Job::tty_read(
  tty : Tty,
  buf : FixedArray[Byte],
  offset : Int32,
  len : Int32,
) -> Job = "moonbitlang_async_make_tty_read_job"

///|
/// Wait until the terminal has input or is resized,
/// then read available input into `buf[offset:offset+len]`.
/// Return the number of bytes read.
/// A zero return value means either EOF or that the wait was interrupted by a resize;
/// `take_resize_event` tells the two apart.
pub async fn Tty::read(
  self : Tty,
  buf : FixedArray[Byte],
  offset~ : Int32,
  len~ : Int32,
  context~ : String,
) -> Int32 {
  @coroutine.check_cancellation()
  let job = Job::tty_read(self, buf, offset, len)
  defer job.free()
  perform_job_in_worker(job, context~, cancellable=true)
}
