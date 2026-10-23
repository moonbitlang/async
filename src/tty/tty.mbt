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
/// A handle on the controlling terminal of the process.
/// Obtain it with `open()`.
struct Tty {
  handle : @event_loop.Tty
  out_fd : @fd_util.Fd
  /// The output `IoHandle`, created lazily for the current event loop
  /// and detached when the loop exits.
  mut out : @event_loop.IoHandle?
  read_buf : @io.ReaderBuffer
  event_buf : FixedArray[Byte]
  mut reading : Bool
  /// A resize observed by a plain `read`, to be reported by the next `read_event`.
  mut resize_pending : Bool
}

///|
/// An event from the terminal, see `Tty::read_event`.
pub(all) enum Event {
  /// Bytes sent by the terminal, exactly as received. Never empty.
  Input(Bytes)
  /// The terminal window was resized. Consecutive resizes may be coalesced.
  /// Call `Tty::size` to get the new dimensions.
  Resize
} derive(Debug, Eq)

///|
let instance : Ref[Tty?] = Ref(None)

///|
/// Open the controlling terminal of the process.
///
/// The terminal is opened on the first call and the same handle is returned
/// on every later call. It stays open for the rest of the process.
/// `stdin`/`stdout` are not consulted: this always opens the terminal itself,
/// and fails if the process has no controlling terminal.
///
/// Raw mode is left automatically when the event loop exits.
pub fn open() -> Tty raise {
  if instance.val is Some(tty) {
    return tty
  }
  let tty = Tty::open_path(b"/dev/tty", context="@tty.open()")
  instance.val = Some(tty)
  @event_loop.register_hook(exit=() => {
    tty.leave_raw_mode() catch {
      _ => ()
    }
    tty.detach()
  })
  tty
}

///|
fn Tty::open_path(path : Bytes, context~ : String) -> Tty raise {
  let (handle, out_fd) = @event_loop.Tty::open(path, context~)
  {
    handle,
    out_fd,
    out: None,
    read_buf: @io.ReaderBuffer::new(),
    event_buf: FixedArray::make(4096, b'\x00'),
    reading: false,
    resize_pending: false,
  }
}

///|
/// Put the terminal into raw mode: no echo, no line buffering,
/// no signal generation from keys (so Ctrl-C arrives as byte `0x03`),
/// no output post-processing.
///
/// The terminal state before the first call is saved,
/// calling this again before `leave_raw_mode` is a no-op.
pub fn Tty::enter_raw_mode(self : Tty) -> Unit raise {
  self.handle.enter_raw(context="@tty.Tty::enter_raw_mode()")
}

///|
/// Restore the terminal state saved by `enter_raw_mode`.
/// No-op if the terminal is not in raw mode.
pub fn Tty::leave_raw_mode(self : Tty) -> Unit raise {
  self.handle.leave_raw(context="@tty.Tty::leave_raw_mode()")
}

///|
/// The size of the terminal window as `(rows, cols)`.
pub fn Tty::size(self : Tty) -> (Int32, Int32) raise {
  self.handle.size(context="@tty.Tty::size()")
}

///|
async fn Tty::read_once(
  self : Tty,
  buf : FixedArray[Byte],
  offset~ : Int32,
  len~ : Int32,
  context~ : String,
) -> Int32 {
  // Like concurrent reads on any other `IoHandle`, this is a usage error.
  guard! !self.reading
  self.reading = true
  defer {
    self.reading = false
  }
  self.handle.read(buf, offset~, len~, context~)
}

///|
/// Wait for the next event from the terminal: input bytes or a resize.
/// Return `None` on EOF.
///
/// Only one read (`read_event` or the `@io.Reader` methods)
/// may be in progress at a time, starting another one aborts the program.
pub async fn Tty::read_event(self : Tty) -> Event? {
  if self.resize_pending || self.handle.take_resize_event() {
    self.resize_pending = false
    return Some(Resize)
  }
  let n = self.read_once(
    self.event_buf,
    offset=0,
    len=self.event_buf.length(),
    context="@tty.Tty::read_event()",
  )
  if n > 0 {
    return Some(Input(Bytes::from_array(self.event_buf[:n])))
  }
  if self.handle.take_resize_event() {
    return Some(Resize)
  }
  None
}

///|
pub impl @io.Reader for Tty with fn _direct_read(self, buf, offset~, max_len~) {
  for ;; {
    let n = self.read_once(
      buf,
      offset~,
      len=max_len,
      context="@tty.Tty::read()",
    )
    if n > 0 {
      return n
    }
    // A resize interrupted the wait. Remember it for `read_event` and keep reading.
    guard self.handle.take_resize_event() else { return 0 }
    self.resize_pending = true
  }
}

///|
pub impl @io.Reader for Tty with fn _get_internal_buffer(self) {
  self.read_buf
}

///|
pub extend Tty with @io.Reader::{
  read,
  read_some,
  drop,
  read_all,
  read_until,
  read_exactly,
}

///|
fn Tty::output(self : Tty) -> @event_loop.IoHandle raise {
  if self.out is Some(out) {
    return out
  }
  let out = @event_loop.IoHandle::from_fd(
    self.out_fd,
    kind=@event_loop.tty_output_kind,
    is_async=false,
  )
  self.out = Some(out)
  out
}

///|
pub impl @io.Writer for Tty with fn write_once(self, buf, offset~, len~) {
  self.output().write(buf, offset~, len~, context="@tty.Tty::write()")
}

///|
pub extend Tty with @io.Writer::{write_once, write, write_reader}

///|
/// Detach the output handle from the current event loop, without closing it.
fn Tty::detach(self : Tty) -> Unit {
  if self.out is Some(out) {
    out.detach_from_event_loop()
    self.out = None
  }
}
