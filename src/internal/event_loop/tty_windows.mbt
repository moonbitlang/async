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
/// Terminal resizes read from console input records, reported by `Tty::read`
#cfg(platform="windows")
priv struct Resize {
  /// a resize not yet reported by `Tty::read`
  mut pending : Bool
}

///|
#cfg(platform="windows")
fn Resize::new() -> Resize {
  { pending: false, }
}

///|
/// There is no `SIGWINCH` on Windows
#cfg(platform="windows")
fn Resize::notify(self : Resize) -> Unit {
  ignore(self)
}

///|
/// The reading side of a terminal opened by `@tty`.
#cfg(platform="windows")
struct Tty {
  input : IoHandle
  /// an event for cancelling a console read
  mut wakeup : @fd_util.Fd
  console_buffer : TtyConsoleBuffer
}

///|
/// Like `WindowsConsoleBuffer`, but `pending` can hold several characters
#cfg(platform="windows")
priv struct TtyConsoleBuffer {
  buffer : FixedArray[UInt16]
  mut unpaired_surrogate : UInt16
  pending : FixedArray[Byte]
  mut pending_offset : Int32
  mut pending_len : Int32
}

///|
#cfg(platform="windows")
fn TtyConsoleBuffer::TtyConsoleBuffer() -> TtyConsoleBuffer {
  {
    buffer: FixedArray::make(WINDOWS_CONSOLE_BUFFER_SIZE, 0),
    unpaired_surrogate: 0,
    pending: FixedArray::make(8, 0),
    pending_offset: 0,
    pending_len: 0,
  }
}

///|
#cfg(platform="windows")
fn TtyConsoleBuffer::write_pending(
  self : TtyConsoleBuffer,
  buf : FixedArray[Byte],
  offset~ : Int32,
  len~ : Int32,
) -> Int32 {
  let n = @cmp.minimum(self.pending_len, len)
  self.pending.blit_to(
    buf,
    src_offset=self.pending_offset,
    dst_offset=offset,
    len=n,
  )
  self.pending_len -= n
  self.pending_offset = if self.pending_len > 0 {
    self.pending_offset + n
  } else {
    0
  }
  n
}

///|
/// Write `char` to `buf`, or to `pending` if it does not fit.
/// Return the new number of bytes written to `buf`.
#cfg(platform="windows")
fn TtyConsoleBuffer::emit(
  self : TtyConsoleBuffer,
  char : Int32,
  buf : FixedArray[Byte],
  offset~ : Int32,
  len~ : Int32,
  produced~ : Int32,
) -> Int32 {
  let char_bytes = match char {
    _..<0x80 => 1
    _..<0x800 => 2
    _..<0x10000 => 3
    _ => 4
  }
  if self.pending_len == 0 && produced + char_bytes <= len {
    encode_utf8_char(char, buf, offset=offset + produced)
    produced + char_bytes
  } else {
    encode_utf8_char(char, self.pending, offset=self.pending_len)
    self.pending_len += char_bytes
    produced
  }
}

///|
/// Convert `buffer[:n]` to UTF-8 in `buf`. Return the number of bytes written.
#cfg(platform="windows")
fn TtyConsoleBuffer::decode(
  self : TtyConsoleBuffer,
  n : Int32,
  buf : FixedArray[Byte],
  offset~ : Int32,
  len~ : Int32,
) -> Int32 {
  let mut produced = 0
  for unit in self.buffer[:n] {
    let high = self.unpaired_surrogate
    match unit {
      0xD800..<=0xDBFF => {
        if high != 0 {
          produced = self.emit(0xFFFD, buf, offset~, len~, produced~)
        }
        self.unpaired_surrogate = unit
      }
      0xDC00..<=0xDFFF => {
        let char = if high != 0 {
          ((high.to_int() - 0xD800) << 10) + (unit.to_int() - 0xDC00) + 0x10000
        } else {
          0xFFFD
        }
        self.unpaired_surrogate = 0
        produced = self.emit(char, buf, offset~, len~, produced~)
      }
      _ => {
        if high != 0 {
          self.unpaired_surrogate = 0
          produced = self.emit(0xFFFD, buf, offset~, len~, produced~)
        }
        produced = self.emit(unit.to_int(), buf, offset~, len~, produced~)
      }
    }
  }
  produced +
  self.write_pending(buf, offset=offset + produced, len=len - produced)
}

///|
#cfg(platform="windows")
pub fn Tty::new(input~ : IoHandle, wakeup~ : @fd_util.Fd) -> Tty {
  { input, wakeup, console_buffer: TtyConsoleBuffer(), }
}

///|
#cfg(platform="windows")
pub fn Tty::close(self : Tty) -> Unit {
  self.input.close()
  if @fd_util.fd_is_valid(self.wakeup) {
    @fd_util.close(self.wakeup, kind=CharDevice, context="") catch {
      _ => ()
    }
    self.wakeup = @fd_util.invalid_fd
  }
}

///|
/// Read input, or return `-1` for a resize in `raw` mode.
#cfg(platform="windows")
async fn Tty::read_input(
  self : Tty,
  buf : FixedArray[Byte],
  offset~ : Int32,
  len~ : Int32,
  raw~ : Bool,
  block_resize~ : Bool,
  context~ : String,
) -> Int32 {
  ignore(block_resize)
  let console = self.console_buffer
  if console.pending_len > 0 {
    return console.write_pending(buf, offset~, len~)
  }
  if raw {
    self.read_console_input(buf, offset~, len~, context~)
  } else {
    self.input.read(buf, offset~, len~, context~)
  }
}

///|
#cfg(platform="windows")
async fn Tty::read_console_input(
  self : Tty,
  buf : FixedArray[Byte],
  offset~ : Int32,
  len~ : Int32,
  context~ : String,
) -> Int32 {
  let console = self.console_buffer
  let max_len = @cmp.minimum(console.buffer.length(), @cmp.maximum(len / 3, 3))
  for ;; {
    let job = TtyReadConsoleInputJob::new(
      self.input.fd,
      self.wakeup,
      console.buffer,
      0,
      max_len,
    )
    defer job.0.free()
    let n = perform_job_in_worker(job.0, context~, cancellable=true)
    if n < 0 {
      return n
    }
    let produced = console.decode(n, buf, offset~, len~)
    if job.resized() {
      if produced == 0 {
        return -1
      }
      guard! curr_loop.val is Some(evloop)
      evloop.resize.pending = true
    }
    if produced > 0 {
      return produced
    }
  }
}

///|
#cfg(platform="windows")
#owned(buf)
extern "C" fn TtyReadConsoleInputJob::new(
  input : @fd_util.Fd,
  wakeup : @fd_util.Fd,
  buf : FixedArray[UInt16],
  offset : Int32,
  len : Int32,
) -> TtyReadConsoleInputJob = "moonbitlang_async_make_tty_read_console_input_job"

///|
#cfg(platform="windows")
priv struct TtyReadConsoleInputJob(Job)

///|
#cfg(platform="windows")
extern "C" fn TtyReadConsoleInputJob::resized(
  job : TtyReadConsoleInputJob,
) -> Bool = "moonbitlang_async_tty_read_console_input_job_get_resized"
