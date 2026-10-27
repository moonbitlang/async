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
/// The controlling terminal of the process, obtained with `open()`.
struct Tty {
  /// the input descriptor on Unix, `CONOUT$` on Windows
  mut control_fd : @fd_util.Fd
  /// the terminal state saved by `enter_raw_mode`
  mut state : FixedArray[Byte]?
  tty : @event_loop.Tty
  output : @event_loop.IoHandle
  read_buf : @io.ReaderBuffer
  mut reading : Bool
}

///|
/// An event from the terminal, see `Tty::read_event`.
pub(all) enum Event {
  /// Raw bytes from the terminal, never empty
  Input(Bytes)
  /// The window was resized, consecutive resizes may be coalesced
  Resize
} derive(Debug, Eq)

///|
/// The terminal of the running event loop, closed when the loop exits.
let instance : Ref[Tty?] = {
  let instance : Ref[Tty?] = Ref(None)
  @event_loop.register_hook(exit=() => {
    guard instance.val is Some(tty) else { return }
    instance.val = None
    tty.leave_raw_mode() catch {
      _ => ()
    }
    tty.close()
  })
  instance
}

///|
/// Open the controlling terminal of the process: `/dev/tty` on Unix,
/// the console on Windows. Fails if there is no controlling terminal.
///
/// Every call in the same event loop returns the _same_ `Tty`,
/// because all handles of a terminal share its mode, input and resize signal.
/// The terminal is restored and closed when the event loop exits.
pub async fn open() -> Tty {
  @coroutine.check_cancellation()
  if instance.val is Some(tty) {
    return tty
  }
  let tty = Tty::open(context="@tty.open()")
  instance.val = Some(tty)
  tty
}

///|
/// Fill `fds` with `[input_fd, wakeup_fd, control_fd, output_fd]`
#borrow(fds)
extern "C" fn tty_open(fds : FixedArray[@fd_util.Fd]) -> Int32 = "moonbitlang_async_tty_open"

///|
fn Tty::open(context~ : String) -> Tty raise {
  let fds = FixedArray::make(4, @fd_util.invalid_fd)
  if tty_open(fds) < 0 {
    @os_error.check_errno(context)
  }
  guard! fds is [input_fd, wakeup_fd, control_fd, output_fd]
  let output = @event_loop.IoHandle::from_fd(
    output_fd,
    kind=if @event_loop.platform is Windows { Console } else { CharDevice },
    is_async=false,
  )
  {
    control_fd,
    state: None,
    tty: @event_loop.Tty::new(input_fd~, wakeup_fd~),
    output,
    read_buf: @io.ReaderBuffer::new(),
    reading: false,
  }
}

///|
fn Tty::close(self : Tty) -> Unit {
  self.output.close()
  // on Unix, `control_fd` is the input descriptor closed by `self.tty`
  if @event_loop.platform is Windows {
    @fd_util.close(self.control_fd, kind=Console, context="") catch {
      _ => ()
    }
  }
  self.control_fd = @fd_util.invalid_fd
  self.tty.close()
}

///|
/// Put the terminal into raw mode: no echo, no line buffering,
/// no signals from keys and no output post-processing.
/// No-op if the terminal is already in raw mode.
/// On Windows, fails on the legacy console (conhost v1), which has no VT support.
pub fn Tty::enter_raw_mode(self : Tty) -> Unit raise {
  guard self.state is None else { return }
  let state = FixedArray::make(tty_state_size, b'\x00')
  if tty_enter_raw(self.tty.input_fd(), self.control_fd, 0, state) < 0 {
    @os_error.check_errno("@tty.Tty::enter_raw_mode()")
  }
  self.state = Some(state)
}

///|
/// The size of the state saved by `tty_enter_raw`
let tty_state_size : Int32 = tty_state_size_ffi()

///|
extern "C" fn tty_state_size_ffi() -> Int32 = "moonbitlang_async_tty_state_size"

///|
/// Save the old state to `state`
#borrow(state)
extern "C" fn tty_enter_raw(
  input : @fd_util.Fd,
  output : @fd_util.Fd,
  flags : Int32,
  state : FixedArray[Byte],
) -> Int32 = "moonbitlang_async_tty_enter_raw"

///|
/// Restore the terminal state saved by `enter_raw_mode`.
pub fn Tty::leave_raw_mode(self : Tty) -> Unit raise {
  guard self.state is Some(state) else { return }
  if tty_leave_raw(self.tty.input_fd(), self.control_fd, state) < 0 {
    @os_error.check_errno("@tty.Tty::leave_raw_mode()")
  }
  self.state = None
}

///|
#borrow(state)
extern "C" fn tty_leave_raw(
  input : @fd_util.Fd,
  output : @fd_util.Fd,
  state : FixedArray[Byte],
) -> Int32 = "moonbitlang_async_tty_leave_raw"

///|
/// The size of the terminal window as `(rows, cols)`.
pub fn Tty::size(self : Tty) -> (Int32, Int32) raise {
  tty_size(self.control_fd, context="@tty.Tty::size()")
}

///|
extern "C" fn tty_size_ffi(output : @fd_util.Fd) -> Int64 = "moonbitlang_async_tty_size"

///|
fn tty_size(output : @fd_util.Fd, context~ : String) -> (Int32, Int32) raise {
  let packed = tty_size_ffi(output)
  if packed < 0 {
    @os_error.check_errno(context)
  }
  ((packed >> 32).to_int(), (packed & 0xFFFF).to_int())
}

///|
/// Return `-1` for a resize, see `@event_loop.Tty::read`.
async fn Tty::read_once(
  self : Tty,
  buf : FixedArray[Byte],
  offset~ : Int32,
  len~ : Int32,
  block_resize~ : Bool,
  context~ : String,
) -> Int32 {
  guard! !self.reading
  self.reading = true
  defer {
    self.reading = false
  }
  self.tty.read(
    buf,
    offset~,
    len~,
    raw=self.state is Some(_),
    block_resize~,
    context~,
  )
}

///|
/// Wait for the next input or resize. Return `None` on EOF.
///
/// Only one read (including the `@io.Reader` methods) may be in progress.
pub async fn Tty::read_event(self : Tty) -> Event? {
  try @io.Reader::read_some(EventReader(self), max_len=4096) catch {
    Resized => Some(Resize)
    err => raise err
  } noraise {
    Some(data) => Some(Input(data))
    None => None
  }
}

///|
priv suberror Resized

///|
/// `Tty` as a reader that raises `Resized` on resize
priv struct EventReader(Tty)

///|
impl @io.Reader for EventReader with fn _get_internal_buffer(self) {
  self.0.read_buf
}

///|
impl @io.Reader for EventReader with fn _direct_read(
  self,
  buf,
  offset~,
  max_len~,
) {
  let n = self.0.read_once(
    buf,
    offset~,
    len=max_len,
    block_resize=false,
    context="@tty.Tty::read_event()",
  )
  guard n >= 0 else { raise Resized }
  n
}

///|
pub impl @io.Reader for Tty with fn _direct_read(self, buf, offset~, max_len~) {
  // leave resizes to `read_event`
  self.read_once(
    buf,
    offset~,
    len=max_len,
    block_resize=true,
    context="@tty.Tty::read()",
  )
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
pub impl @io.Writer for Tty with fn write_once(self, buf, offset~, len~) {
  self.output.write(buf, offset~, len~, context="@tty.Tty::write()")
}

///|
pub extend Tty with @io.Writer::{write_once, write, write_reader}
