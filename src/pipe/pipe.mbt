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
struct PipeRead(Int)

///|
pub fn PipeRead::fd(self : PipeRead) -> Int {
  let PipeRead(fd) = self
  fd
}

///|
/// The write end of a pipe
struct PipeWrite(Int)

///|
pub fn PipeWrite::fd(self : PipeWrite) -> Int {
  let PipeWrite(fd) = self
  fd
}

///|
/// Create a pipe using `pipe(2)` system call.
/// Return the read end and write end of the pipe.
pub fn pipe() -> (PipeRead, PipeWrite) raise {
  let (r, w) = @fd_util.pipe()
  @fd_util.set_nonblocking(r)
  @fd_util.set_nonblocking(w)
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
    @fd_util.set_nonblocking(0) catch {
      _ => ()
    }
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
    @fd_util.set_nonblocking(1) catch {
      _ => ()
    }
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
    @fd_util.set_nonblocking(2) catch {
      _ => ()
    }
  }
  PipeWrite(2)
}

///|
/// Reset the state of standard input/output/error, clearing the non-blocking flag.
/// For console applications, this prevents the parent process from also entering non-blocking mode.
/// If stdio is already in non-blocking mode, this function does nothing.
pub fn reset_stdio() -> Unit {
  for fd in stdio_need_reset {
    @fd_util.set_blocking(fd) catch {
      _ => ()
    }
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
pub impl @io.Reader for PipeRead with read(self, buf, offset~, max_len~) {
  let PipeRead(fd) = self
  @event_loop.prepare_fd_read(fd)
  let n_read = read_ffi(fd, buf, offset, max_len)
  let n_read = if n_read < 0 && @os_error.is_nonblocking_io_error() {
    @event_loop.wait_fd_read(fd)
    read_ffi(fd, buf, offset, max_len)
  } else {
    @async.pause()
    n_read
  }
  if n_read < 0 {
    @os_error.check_errno()
  }
  n_read
}

///|
/// Read data from the read end of a pipe using `read(2)` system call.
/// For `pipe.read(buf, offset~, max_len~)`,
/// at most `max_len` bytes of data will be written to `buf`, starting from `offset`.
/// The number of read bytes will be returned.
///
/// At most one task can read from a pipe at any time.
/// To allow multiple reader,
/// use a worker task for reading and use `@async.Queue` to distribute the data.
pub async fn PipeRead::read(
  self : PipeRead,
  buf : FixedArray[Byte],
  offset~ : Int = 0,
  max_len~ : Int = buf.length() - offset,
) -> Int raise {
  @io.Reader::read(self, buf, offset~, max_len~)
}

///|
/// `pipe.read_exactly(n)` read exactly `n` bytes of data from a pipe.
/// `read_exactly` will only return after all `n` bytes of data are read.
/// If the pipe is closed before receiving all data, an error is raised.
///
/// At most one task can read from a pipe at any time.
/// To allow multiple reader,
/// use a worker task for reading and use `@async.Queue` to distribute the data.
pub async fn PipeRead::read_exactly(self : PipeRead, len : Int) -> Bytes raise {
  @io.Reader::read_exactly(self, len)
}

///|
/// Write data through the write end of a pipe using `write(2)` system call.
/// This function will only return after all data have been successfully written.
///
/// At most one task can write to a pipe at any time.
/// To allow multiple writers,
/// use a worker task for writing and use `@async.Queue` to gather data.
pub async fn PipeWrite::write(
  self : PipeWrite,
  buf : Bytes,
  offset~ : Int = 0,
  len~ : Int = buf.length() - offset,
) -> Unit raise {
  let PipeWrite(fd) = self
  @event_loop.prepare_fd_write(fd)
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
