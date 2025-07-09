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
type PipeRead Int

///|
type PipeWrite Int

///|
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
pub let stdin : PipeRead = {
  ignore(set_nonblock(0))
  PipeRead(0)
}

///|
pub let stdout : PipeWrite = {
  ignore(set_nonblock(1))
  PipeWrite(1)
}

///|
pub let stderr : PipeWrite = {
  ignore(set_nonblock(2))
  PipeWrite(2)
}

///|
pub fn PipeRead::close(self : PipeRead) -> Unit {
  let PipeRead(fd) = self
  if fd < 3 {
    ignore(set_blocking(fd))
  }
  @async.close(fd)
}

///|
pub fn PipeWrite::close(self : PipeWrite) -> Unit {
  let PipeWrite(fd) = self
  @async.close(fd)
}

///|
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
    @async.wait_fd_read(fd)
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
        @async.wait_fd_write(fd)
      } else {
        @os_error.check_errno()
      }
    } else {
      continue sent + new_sent
    }
  }
}
