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
/// The read end of a pipe
type PipeRead Int

///|
pub fn PipeRead::fd(self : PipeRead) -> Int {
  let PipeRead(fd) = self
  fd
}

///|
/// The write end of a pipe
type PipeWrite Int

///|
pub fn PipeWrite::fd(self : PipeWrite) -> Int {
  let PipeWrite(fd) = self
  fd
}

///|
/// Create a pipe using `pipe(2)` system call.
/// Return the read end and write end of the pipe.
pub fn pipe() -> (PipeRead, PipeWrite) raise {
  let fds : FixedArray[Int] = [0, 0]
  if 0 != pipe_ffi(fds) {
    @os_error.check_errno()
  }
  guard fds is [r, w]
  if set_nonblock(r) < 0 {
    @os_error.check_errno()
  }
  if set_nonblock(w) < 0 {
    @os_error.check_errno()
  }
  (PipeRead(r), PipeWrite(w))
}

///|
let stdio_need_reset : Array[Int] = []

///|
/// The standard input treated as a pipe.
/// Using this value will result in standard input being set to non-blocking mode.
/// For console applications, remember to reset the state of standard input
/// using `reset_stdio`, as standard input may be shared between multiple process.
pub let stdin : PipeRead = {
  if get_blocking(0) > 0 {
    stdio_need_reset.push(0)
    ignore(set_nonblock(0))
  }
  PipeRead(0)
}

///|
/// The standard output treated as a pipe.
/// Using this value will result in standard output being set to non-blocking mode.
/// For console applications, remember to reset the state of standard output
/// using `reset_stdio`, as standard output may be shared between multiple process.
pub let stdout : PipeWrite = {
  if get_blocking(1) > 0 {
    stdio_need_reset.push(1)
    ignore(set_nonblock(1))
  }
  PipeWrite(1)
}

///|
/// The standard error treated as a pipe.
/// Using this value will result in standard error being set to non-blocking mode.
/// For console applications, remember to reset the state of standard error
/// using `reset_stdio`, as standard error may be shared between multiple process.
pub let stderr : PipeWrite = {
  if get_blocking(2) > 0 {
    stdio_need_reset.push(2)
    ignore(set_nonblock(2))
  }
  PipeWrite(2)
}

///|
/// Reset the state of standard input/output/error, clearing the non-blocking flag.
/// For console applications, this prevents the parent process from also entering non-blocking mode.
/// If stdio is already in non-blocking mode, this function does nothing.
pub fn reset_stdio() -> Unit {
  for fd in stdio_need_reset {
    ignore(set_blocking(fd))
  }
}

///|
pub fn PipeRead::close(self : PipeRead) -> Unit {
  let PipeRead(fd) = self
  @event_loop.close_fd(fd)
}

///|
pub fn PipeWrite::close(self : PipeWrite) -> Unit {
  let PipeWrite(fd) = self
  @event_loop.close_fd(fd)
}

///|
/// Read data from the read end of a pipe using `read(2)` system call.
/// For `pipe.read(buf, offset~, max_len~)`,
/// at most `max_len` bytes of data will be written to `buf`, starting from `offset`.
/// The number of read bytes will be returned.
pub async fn PipeRead::read(
  self : PipeRead,
  buf : FixedArray[Byte],
  offset~ : Int = 0,
  max_len? : Int,
) -> Int raise {
  let max_len = max_len.unwrap_or(buf.length() - offset)
  let PipeRead(fd) = self
  let n_read = read_ffi(fd, buf, offset, max_len)
  let n_read = if n_read < 0 && @os_error.is_nonblocking_io_error() {
    @event_loop.wait_fd_read(fd)
    read_ffi(fd, buf, offset, max_len)
  } else {
    n_read
  }
  if n_read < 0 {
    @os_error.check_errno()
  }
  n_read
}

///|
pub suberror PipeClosed derive(Show)

///|
/// `pipe.read_exactly(n)` read exactly `n` bytes of data from a pipe.
/// `read_exactly` will only return after all `n` bytes of data are read.
/// If the pipe is closed before receiving all data, an error is raised.
pub async fn PipeRead::read_exactly(self : PipeRead, len : Int) -> Bytes raise {
  let buf = FixedArray::make(len, (0 : Byte))
  for received = 0; received < len; {
    let new_received = self.read(buf, offset=received, max_len=len - received)
    if new_received == 0 {
      raise PipeClosed
    }
    continue received + new_received
  }
  buf.unsafe_reinterpret_as_bytes()
}

///|
/// Write data through the write end of a pipe using `write(2)` system call.
/// This function will only return after all data have been successfully written.
pub async fn PipeWrite::write(
  self : PipeWrite,
  buf : Bytes,
  offset~ : Int = 0,
  len? : Int,
) -> Unit raise {
  let len = len.unwrap_or(buf.length() - offset)
  let PipeWrite(fd) = self
  for sent = 0; sent < len; {
    let new_sent = write_ffi(fd, buf, offset + sent, len - sent)
    if new_sent < 0 {
      if @os_error.is_nonblocking_io_error() {
        @event_loop.wait_fd_write(fd)
      } else {
        @os_error.check_errno()
      }
    } else {
      continue sent + new_sent
    }
  }
}
