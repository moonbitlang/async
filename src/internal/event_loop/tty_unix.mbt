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
  guard! curr_loop.val is Some(evloop)
  for ;; {
    if !block_resize {
      if evloop.resize.pending {
        evloop.resize.pending = false
        return -1
      }
      // `SIGWINCH` wakes the wait for input in `read`
      evloop.resize.waiter = Some(@coroutine.current_coroutine())
    }
    defer {
      evloop.resize.waiter = None
    }
    return self.input.read(buf, offset~, len~, context~) catch {
      // woken by a resize, or the input was taken by another reader
      @os_error.OSError(_, ..) as err if err.is_nonblocking_io_error() =>
        continue
      err => raise err
    }
  }
}
