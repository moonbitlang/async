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
/// The terminal is closed when the event loop exits, but its state is not
/// restored: undo `set_state` with `defer`, see `Tty::set_state`.
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
/// Return the name of the controlling terminal under `/dev/`, or null on error.
/// It is owned by the C library and must not be freed.
#cfg(not(platform="windows"))
extern "C" fn tty_name() -> @c_buffer.Buffer = "moonbitlang_async_tty_name"

///|
#cfg(not(platform="windows"))
async fn Tty::open(context~ : String) -> Tty {
  let name = tty_name()
  if name.is_null() {
    @os_error.check_errno(context)
  }
  let path = "/dev/\{@os_string.decode(name)}"
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
  {
    tty: @event_loop.Tty::new(input=io),
    output: io,
    read_buf: @io.ReaderBuffer::new(),
    reading: false,
  }
}

///|
#cfg(platform="windows")
let _ignore_unused_import : Unit = {
  ignore(@c_buffer.Buffer::is_null)
  ignore(@os_string.encode)
}

///|
#cfg(platform="windows")
async fn Tty::open(context~ : String) -> Tty {
  let (input, _) = @event_loop.open(
    "CONIN$",
    2,
    create=0,
    append=false,
    sync=0,
    mode=0,
    context~,
  )
  errdefer input.close()
  let (output, _) = @event_loop.open(
    "CONOUT$",
    2,
    create=0,
    append=false,
    sync=0,
    mode=0,
    context~,
  )
  {
    tty: @event_loop.Tty::new(input~),
    output,
    read_buf: @io.ReaderBuffer::new(),
    reading: false,
  }
}

///|
fn Tty::close(self : Tty) -> Unit {
  self.output.close()
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
/// `c_iflag` flags of `termios`. Those that differ between Linux and macOS are
/// matched on the platform.
const IGNBRK : UInt64 = 0x1

///|
const BRKINT : UInt64 = 0x2

///|
const IGNPAR : UInt64 = 0x4

///|
const PARMRK : UInt64 = 0x8

///|
const INPCK : UInt64 = 0x10

///|
const ISTRIP : UInt64 = 0x20

///|
const INLCR : UInt64 = 0x40

///|
const IGNCR : UInt64 = 0x80

///|
const ICRNL : UInt64 = 0x100

///|
let ixon : UInt64 = match @event_loop.platform {
  Linux => 0x400
  MacOS => 0x200
  Windows => 0
}

///|
let ixoff : UInt64 = match @event_loop.platform {
  Linux => 0x1000
  MacOS => 0x400
  Windows => 0
}

///|
const IMAXBEL : UInt64 = 0x2000

///|
/// `c_oflag` flags of `termios`
const OPOST : UInt64 = 0x1

///|
/// `c_cflag` flags of `termios`
let csize : UInt64 = match @event_loop.platform {
  Linux => 0x30
  MacOS => 0x300
  Windows => 0
}

///|
let cs8 : UInt64 = match @event_loop.platform {
  Linux => 0x30
  MacOS => 0x300
  Windows => 0
}

///|
let cread : UInt64 = match @event_loop.platform {
  Linux => 0x80
  MacOS => 0x800
  Windows => 0
}

///|
let parenb : UInt64 = match @event_loop.platform {
  Linux => 0x100
  MacOS => 0x1000
  Windows => 0
}

///|
/// `c_lflag` flags of `termios`
let isig : UInt64 = match @event_loop.platform {
  Linux => 0x1
  MacOS => 0x80
  Windows => 0
}

///|
let icanon : UInt64 = match @event_loop.platform {
  Linux => 0x2
  MacOS => 0x100
  Windows => 0
}

///|
const ECHO : UInt64 = 0x8

///|
let echoe : UInt64 = match @event_loop.platform {
  Linux => 0x10
  MacOS => 0x2
  Windows => 0
}

///|
let echok : UInt64 = match @event_loop.platform {
  Linux => 0x20
  MacOS => 0x4
  Windows => 0
}

///|
let echonl : UInt64 = match @event_loop.platform {
  Linux => 0x40
  MacOS => 0x10
  Windows => 0
}

///|
let noflsh : UInt64 = match @event_loop.platform {
  Linux => 0x80
  MacOS => 0x80000000
  Windows => 0
}

///|
let tostop : UInt64 = match @event_loop.platform {
  Linux => 0x100
  MacOS => 0x400000
  Windows => 0
}

///|
let pendin : UInt64 = match @event_loop.platform {
  Linux => 0x4000
  MacOS => 0x20000000
  Windows => 0
}

///|
let iexten : UInt64 = match @event_loop.platform {
  Linux => 0x8000
  MacOS => 0x400
  Windows => 0
}

///|
/// Windows console input mode flags
const ENABLE_PROCESSED_INPUT : UInt32 = 0x1

///|
const ENABLE_LINE_INPUT : UInt32 = 0x2

///|
const ENABLE_ECHO_INPUT : UInt32 = 0x4

///|
const ENABLE_WINDOW_INPUT : UInt32 = 0x8

///|
const ENABLE_QUICK_EDIT_MODE : UInt32 = 0x40

///|
const ENABLE_EXTENDED_FLAGS : UInt32 = 0x80

///|
const ENABLE_VIRTUAL_TERMINAL_INPUT : UInt32 = 0x200

///|
/// Windows console output mode flags
const ENABLE_PROCESSED_OUTPUT : UInt32 = 0x1

///|
const ENABLE_VIRTUAL_TERMINAL_PROCESSING : UInt32 = 0x4

///|
const DISABLE_NEWLINE_AUTO_RETURN : UInt32 = 0x8

///|
/// The raw mode of `self`: no echo, no line buffering,
/// no signals from keys and no output post-processing, as `cfmakeraw` in C.
/// Reads return as soon as one byte is available.
/// On Windows it also turns on VT input and output.
pub fn State::make_raw(self : State) -> State {
  let raw = @buffer.Buffer(size_hint=self.0.length())
  match (@event_loop.platform, self.0) {
    // glibc `cfmakeraw` on the kernel `struct termios2`
    (Linux, [u32le(iflag), u32le(oflag), u32le(cflag), u32le(lflag), .. rest]) => {
      let iflag_clear = IGNBRK |
        BRKINT |
        PARMRK |
        ISTRIP |
        INLCR |
        IGNCR |
        ICRNL |
        ixon
      raw.write_uint_le(iflag & iflag_clear.to_uint().lnot())
      raw.write_uint_le(oflag & OPOST.to_uint().lnot())
      raw.write_uint_le(
        (cflag & (csize | parenb).to_uint().lnot()) | cs8.to_uint(),
      )
      let lflag_clear = ECHO | echonl | icanon | isig | iexten
      raw.write_uint_le(lflag & lflag_clear.to_uint().lnot())
      // `c_line`, then `c_cc` with VTIME = 5 and VMIN = 6
      raw.write_bytesview(rest[:6])
      raw.write_byte(0) // VTIME
      raw.write_byte(1) // VMIN
      raw.write_bytesview(rest[8:])
    }
    // macOS `cfmakeraw` on `struct termios`
    (MacOS, [u64le(iflag), u64le(oflag), u64le(cflag), u64le(lflag), .. rest]) => {
      let iflag_clear = IMAXBEL |
        ixoff |
        INPCK |
        BRKINT |
        PARMRK |
        ISTRIP |
        INLCR |
        IGNCR |
        ICRNL |
        ixon |
        IGNPAR
      raw.write_uint64_le((iflag & iflag_clear.lnot()) | IGNBRK)
      raw.write_uint64_le(oflag & OPOST.lnot())
      raw.write_uint64_le((cflag & (csize | parenb).lnot()) | cs8 | cread)
      let lflag_clear = ECHO |
        echoe |
        echok |
        echonl |
        icanon |
        isig |
        iexten |
        noflsh |
        tostop |
        pendin
      raw.write_uint64_le(lflag & lflag_clear.lnot())
      // `c_cc` with VMIN = 16 and VTIME = 17
      raw.write_bytesview(rest[:16])
      raw.write_byte(1) // VMIN
      raw.write_byte(0) // VTIME
      raw.write_bytesview(rest[18:])
    }
    (Windows, [u32le(input), u32le(output)]) => {
      let clear = ENABLE_PROCESSED_INPUT |
        ENABLE_LINE_INPUT |
        ENABLE_ECHO_INPUT |
        ENABLE_QUICK_EDIT_MODE
      let set = ENABLE_WINDOW_INPUT |
        ENABLE_EXTENDED_FLAGS |
        ENABLE_VIRTUAL_TERMINAL_INPUT
      raw.write_uint_le((input & clear.lnot()) | set)
      raw.write_uint_le(
        output |
        ENABLE_PROCESSED_OUTPUT |
        ENABLE_VIRTUAL_TERMINAL_PROCESSING |
        DISABLE_NEWLINE_AUTO_RETURN,
      )
    }
    _ => abort("@tty.State::make_raw(): unexpected state size")
  }
  State(raw.to_bytes())
}

///|
/// Whether line input is off in `self`, as in `State::make_raw`.
/// On Windows VT input must also be on to read console input records,
/// which otherwise carry a held key as a repeat count.
fn State::is_raw(self : State) -> Bool {
  match (@event_loop.platform, self.0) {
    (Linux, [u32le(_), u32le(_), u32le(_), u32le(lflag), ..]) =>
      (lflag & icanon.to_uint()) == 0
    (MacOS, [u64le(_), u64le(_), u64le(_), u64le(lflag), ..]) =>
      (lflag & icanon) == 0
    (Windows, [u32le(input), ..]) =>
      (input & ENABLE_LINE_INPUT) == 0 &&
      (input & ENABLE_VIRTUAL_TERMINAL_INPUT) != 0
    _ => abort("@tty.State::is_raw(): unexpected state size")
  }
}

///|
/// The current state of the terminal.
pub fn Tty::get_state(self : Tty) -> State raise {
  let buf = FixedArray::make(state_size(), b'\x00')
  if tty_get_state(self.tty.input_fd(), self.output.fd(), buf) < 0 {
    @os_error.check_errno("@tty.Tty::get_state()")
  }
  State(buf.unsafe_reinterpret_as_bytes())
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
  if tty_set_state(self.tty.input_fd(), self.output.fd(), state.0) < 0 {
    @os_error.check_errno("@tty.Tty::set_state()")
  }
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
  let packed = tty_size(self.output.fd())
  if packed < 0 {
    @os_error.check_errno("@tty.Tty::size()")
  }
  ((packed >> 32).to_int(), (packed & 0xFFFF).to_int())
}

///|
/// `rows << 32 | cols`, or `-1` on error
extern "C" fn tty_size(output : @fd_util.Fd) -> Int64 = "moonbitlang_async_tty_size"

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
    raw=self.get_state().is_raw(),
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
