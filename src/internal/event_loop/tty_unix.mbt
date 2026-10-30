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
/// Terminal resizes seen by the event loop, reported by `Tty::read`
#cfg(not(platform="windows"))
priv struct Resize {
  /// a resize not yet reported by `Tty::read`
  mut pending : Bool
  /// the `Tty::read` waiting for input that a resize should wake
  mut waiter : @coroutine.Coroutine?
}

///|
#cfg(not(platform="windows"))
fn Resize::new() -> Resize {
  { pending: false, waiter: None, }
}

///|
/// Record a `SIGWINCH` and wake the `Tty::read` waiting for it
#cfg(not(platform="windows"))
fn Resize::notify(self : Resize) -> Unit {
  self.pending = true
  if self.waiter is Some(coro) {
    coro.wake()
  }
}

///|
/// The reading side of a terminal opened by `@tty`.
#cfg(not(platform="windows"))
struct Tty {
  /// non-blocking and registered to the event bus
  input : IoHandle
}

///|
#cfg(not(platform="windows"))
pub fn Tty::new(input~ : IoHandle) -> Tty {
  { input, }
}

///|
#cfg(not(platform="windows"))
pub fn Tty::close(self : Tty) -> Unit {
  self.input.close()
}

///|
#cfg(not(platform="windows"))
pub fn Tty::input_fd(self : Tty) -> @fd_util.Fd {
  self.input.fd()
}

///|
/// Wait for input or a resize, then read input.
/// Return `-1` for a resize, which may be reported after later input.
/// With `block_resize`, like a blocked signal, a resize does not end the wait
/// and stays pending until a read without `block_resize`.
#cfg(not(platform="windows"))
pub async fn Tty::read(
  self : Tty,
  buf : FixedArray[Byte],
  offset~ : Int32,
  len~ : Int32,
  block_resize~ : Bool,
  context~ : String,
) -> Int32 {
  @coroutine.check_cancellation()
  let resize = resize_state.val.unwrap()
  for ;; {
    if !block_resize && resize.pending {
      resize.pending = false
      return -1
    }
    let n = read_unix_ffi(self.input.fd, buf, offset~, len~)
    if n >= 0 {
      // Like `read_via_event_bus_unix`, give other tasks a chance to run.
      @coroutine.pause_nocancel()
      return n
    }
    if !@os_error.is_nonblocking_io_error() {
      @os_error.check_errno(context)
    }
    // `SIGWINCH` wakes the wait for input; the loop then checks
    // `resize.pending` itself instead of guessing from a failed read.
    if !block_resize {
      resize.waiter = Some(@coroutine.current_coroutine())
    }
    defer {
      resize.waiter = None
    }
    self.input.wait_read()
  }
}
