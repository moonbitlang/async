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
  /// the terminal descriptor on Unix, `CONOUT$` on Windows
  mut control_fd : @fd_util.Fd
  /// the state applied by `set_state`, or read by `get_state`
  mut state : State
  /// the state when the terminal was opened, restored on exit
  original : State
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
    if tty.state.0 != tty.original.0 {
      tty.set_state(tty.original) catch {
        _ => ()
      }
    }
    tty.close()
  })
  instance
}

///|
/// Open the controlling terminal of the process: `/dev/tty` on Linux,
/// the terminal device behind it on macOS, the console on Windows.
/// Fails if there is no controlling terminal.
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
  // another `open()` may have finished while this one was opening
  if instance.val is Some(other) {
    tty.close()
    return other
  }
  instance.val = Some(tty)
  tty
}

///|
/// Write the path of the controlling terminal to `path`, return its length
#cfg(not(platform="windows"))
#borrow(path)
extern "C" fn tty_path(path : FixedArray[Byte], len : Int32) -> Int32 = "moonbitlang_async_tty_path"

///|
#cfg(not(platform="windows"))
async fn Tty::open(context~ : String) -> Tty {
  let path = FixedArray::make(64, b'\x00')
  let len = tty_path(path, path.length())
  if len < 0 {
    @os_error.check_errno(context)
  }
  // device paths are ASCII
  let path = String::from_iter(path[:len].iter().map(Byte::to_char))
  // pollable, so it is non-blocking and registered to the event bus
  let (io, _) = @event_loop.open(
    path,
    2,
    create=0,
    append=false,
    sync=0,
    mode=0,
    context~,
  )
  errdefer io.close()
  let buf = FixedArray::make(state_size(), b'\x00')
  if tty_get_state(io.fd(), io.fd(), buf) < 0 {
    @os_error.check_errno(context)
  }
  let state = State(buf.unsafe_reinterpret_as_bytes())
  {
    control_fd: io.fd(),
    state,
    original: state,
    tty: @event_loop.Tty::new(input=io),
    output: io,
    read_buf: @io.ReaderBuffer::new(),
    reading: false,
  }
}

///|
/// Fill `fds` with `[input_fd, wakeup_fd, control_fd, output_fd]`
#cfg(platform="windows")
#borrow(fds)
extern "C" fn tty_open(fds : FixedArray[@fd_util.Fd]) -> Int32 = "moonbitlang_async_tty_open"

///|
#cfg(platform="windows")
fn Tty::open(context~ : String) -> Tty raise {
  let fds = FixedArray::make(4, @fd_util.invalid_fd)
  if tty_open(fds) < 0 {
    @os_error.check_errno(context)
  }
  guard! fds is [input_fd, wakeup_fd, control_fd, output_fd]
  let output = @event_loop.IoHandle::from_fd(
    output_fd,
    kind=Console,
    is_async=false,
  )
  let input = @event_loop.IoHandle::from_fd(
    input_fd,
    kind=Console,
    is_async=false,
  )
  let tty = @event_loop.Tty::new(input~, wakeup=wakeup_fd)
  let buf = FixedArray::make(state_size(), b'\x00')
  if tty_get_state(tty.input_fd(), control_fd, buf) < 0 {
    output.close()
    @fd_util.close(control_fd, kind=Console, context="") catch {
      _ => ()
    }
    tty.close()
    @os_error.check_errno(context)
  }
  let state = State(buf.unsafe_reinterpret_as_bytes())
  {
    control_fd,
    state,
    original: state,
    tty,
    output,
    read_buf: @io.ReaderBuffer::new(),
    reading: false,
  }
}

///|
fn Tty::close(self : Tty) -> Unit {
  self.output.close()
  // on Unix, `control_fd` is the descriptor of `output` and `self.tty`
  if @event_loop.platform is Windows {
    @fd_util.close(self.control_fd, kind=Console, context="") catch {
      _ => ()
    }
  }
  self.control_fd = @fd_util.invalid_fd
  self.tty.close()
}

///|
/// A terminal state, as returned by `Tty::get_state` and applied by
/// `Tty::set_state`, like `struct termios` in C.
///
/// The bytes follow the host: the kernel `struct termios2` on Linux,
/// `struct termios` on macOS,
/// and the input and output console modes as little-endian `u32` on Windows.
struct State(Bytes)

///|
fn state_size() -> Int32 {
  match @event_loop.platform {
    Linux => 44
    MacOS => 72
    Windows => 8
  }
}

///|
/// The raw mode of `self`: no echo, no line buffering,
/// no signals from keys and no output post-processing, as `cfmakeraw` in C.
/// Reads return as soon as one byte is available.
/// On Windows it also turns on VT input and output, so applying it fails on
/// the legacy console (conhost v1).
pub fn State::make_raw(self : State) -> State {
  let raw = @buffer.Buffer(size_hint=self.0.length())
  match (@event_loop.platform, self.0) {
    // glibc `cfmakeraw` on the kernel `struct termios2`
    (Linux, [u32le(iflag), u32le(oflag), u32le(cflag), u32le(lflag), .. rest]) => {
      // clear IGNBRK, BRKINT, PARMRK, ISTRIP, INLCR, IGNCR, ICRNL and IXON
      raw.write_uint_le(iflag & 0x5ebU.lnot())
      // clear OPOST
      raw.write_uint_le(oflag & 0x1U.lnot())
      // clear CSIZE and PARENB, set CS8
      raw.write_uint_le((cflag & 0x130U.lnot()) | 0x30)
      // clear ECHO, ECHONL, ICANON, ISIG and IEXTEN
      raw.write_uint_le(lflag & 0x804bU.lnot())
      // `c_line`, then `c_cc` with VTIME = 5 and VMIN = 6
      raw.write_bytesview(rest[:6])
      raw.write_byte(0) // VTIME
      raw.write_byte(1) // VMIN
      raw.write_bytesview(rest[8:])
    }
    // macOS `cfmakeraw` on `struct termios`
    (MacOS, [u64le(iflag), u64le(oflag), u64le(cflag), u64le(lflag), .. rest]) => {
      // clear IMAXBEL, IXOFF, INPCK, BRKINT, PARMRK, ISTRIP, INLCR, IGNCR,
      // ICRNL, IXON and IGNPAR, set IGNBRK
      raw.write_uint64_le((iflag & 0x27feUL.lnot()) | 0x1)
      // clear OPOST
      raw.write_uint64_le(oflag & 0x1UL.lnot())
      // clear CSIZE and PARENB, set CS8 and CREAD
      raw.write_uint64_le((cflag & 0x1300UL.lnot()) | 0xb00)
      // clear ECHO, ECHOE, ECHOK, ECHONL, ICANON, ISIG, IEXTEN, NOFLSH,
      // TOSTOP and PENDIN
      raw.write_uint64_le(lflag & 0xa040059eUL.lnot())
      // `c_cc` with VMIN = 16 and VTIME = 17
      raw.write_bytesview(rest[:16])
      raw.write_byte(1) // VMIN
      raw.write_byte(0) // VTIME
      raw.write_bytesview(rest[18:])
    }
    (Windows, [u32le(input), u32le(output)]) => {
      // clear PROCESSED_INPUT, LINE_INPUT, ECHO_INPUT and QUICK_EDIT_MODE,
      // set WINDOW_INPUT, EXTENDED_FLAGS and VIRTUAL_TERMINAL_INPUT
      raw.write_uint_le((input & 0x47U.lnot()) | 0x288)
      // set PROCESSED_OUTPUT, VIRTUAL_TERMINAL_PROCESSING
      // and DISABLE_NEWLINE_AUTO_RETURN
      raw.write_uint_le(output | 0xd)
    }
    _ => abort("@tty.State::make_raw(): unexpected state size")
  }
  State(raw.to_bytes())
}

///|
/// Whether reads in `self` are console input records, i.e. line input is off.
/// Only meaningful on Windows, where reading takes a different path.
fn State::reads_records(self : State) -> Bool {
  // ENABLE_LINE_INPUT
  @event_loop.platform is Windows &&
  self.0 is [u32le(input), ..] &&
  (input & 0x2) == 0
}

///|
/// The current state of the terminal.
pub fn Tty::get_state(self : Tty) -> State raise {
  let buf = FixedArray::make(state_size(), b'\x00')
  if tty_get_state(self.tty.input_fd(), self.control_fd, buf) < 0 {
    @os_error.check_errno("@tty.Tty::get_state()")
  }
  let state = State(buf.unsafe_reinterpret_as_bytes())
  self.state = state
  state
}

///|
/// Apply `state`, e.g. one returned by `State::make_raw`:
///
/// ```moonbit nocheck
/// let saved = tty.get_state()
/// tty.set_state(saved.make_raw())
/// defer tty.set_state(saved)
/// ```
pub fn Tty::set_state(self : Tty, state : State) -> Unit raise {
  if tty_set_state(self.tty.input_fd(), self.control_fd, state.0) < 0 {
    @os_error.check_errno("@tty.Tty::set_state()")
  }
  self.state = state
}

///|
/// Write the current state to `state`, see `State`
#borrow(state)
extern "C" fn tty_get_state(
  input : @fd_util.Fd,
  output : @fd_util.Fd,
  state : FixedArray[Byte],
) -> Int32 = "moonbitlang_async_tty_get_state"

///|
/// Apply `state`, see `State`
#borrow(state)
extern "C" fn tty_set_state(
  input : @fd_util.Fd,
  output : @fd_util.Fd,
  state : Bytes,
) -> Int32 = "moonbitlang_async_tty_set_state"

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
    raw=self.state.reads_records(),
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
