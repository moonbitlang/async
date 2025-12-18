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
struct PipeRead {
  io : @event_loop.IoHandle
  read_buf : @io.ReaderBuffer
}

///|
pub fn PipeRead::fd(self : PipeRead) -> @fd_util.Fd {
  self.io.fd()
}

///|
/// The write end of a pipe
struct PipeWrite(@event_loop.IoHandle)

///|
pub fn PipeWrite::fd(self : PipeWrite) -> @fd_util.Fd {
  let PipeWrite(io) = self
  io.fd()
}

///|
/// Create a pipe using `pipe(2)` system call.
/// Return the read end and write end of the pipe.
#cfg(not(platform="windows"))
pub fn pipe() -> (PipeRead, PipeWrite) raise {
  let (r, w) = @fd_util.pipe("@pipe.pipe()")
  @fd_util.set_nonblocking(r, context="@pipe.pipe()")
  @fd_util.set_nonblocking(w, context="@pipe.pipe()")
  let r = {
    io: @event_loop.IoHandle::from_fd(r, kind=Pipe),
    read_buf: @io.ReaderBuffer::new(),
  }
  (r, PipeWrite(@event_loop.IoHandle::from_fd(w, kind=Pipe)))
}

///|
#cfg(platform="windows")
extern "C" fn get_current_process_id() -> UInt = "GetCurrentProcessId"

///|
#cfg(platform="windows")
let current_process_id : UInt = get_current_process_id()

///|
#cfg(platform="windows")
#borrow(name)
extern "C" fn create_named_pipe_server(
  name : @os_string.OsString,
) -> @fd_util.Fd = "moonbitlang_async_create_named_pipe_server"

///|
#cfg(platform="windows")
#borrow(name)
extern "C" fn create_named_pipe_client(
  name : @os_string.OsString,
) -> @fd_util.Fd = "moonbitlang_async_create_named_pipe_client"

///|
#cfg(platform="windows")
let pipe_id : Ref[UInt64] = @ref.new(0)

///|
/// Create a pipe using `pipe(2)` system call.
/// Return the read end and write end of the pipe.
#cfg(platform="windows")
pub fn pipe() -> (PipeRead, PipeWrite) raise {
  let context = "@pipe.pipe()"
  pipe_id.val += 1
  let name = @os_string.encode(
    "\\\\.\\pipe\\moonbitlang_async.\{current_process_id}.\{pipe_id.val}",
  )
  let r = {
    let fd = create_named_pipe_server(name)
    if !@fd_util.fd_is_valid(fd) {
      @os_error.check_errno(context)
    }
    @event_loop.IoHandle::from_fd(fd, kind=Pipe) catch {
      err => {
        @fd_util.close(fd, kind=Pipe, context~)
        raise err
      }
    }
  }
  try {
    let w = {
      let fd = create_named_pipe_client(name)
      if !@fd_util.fd_is_valid(fd) {
        @os_error.check_errno(context)
      }
      @event_loop.IoHandle::from_fd(fd, kind=Pipe) catch {
        err => {
          @fd_util.close(fd, kind=Pipe, context~)
          raise err
        }
      }
    }
    ({ io: r, read_buf: @io.ReaderBuffer::new() }, PipeWrite(w))
  } catch {
    err => {
      r.close()
      raise err
    }
  }
}

///|
// mute unused warning
#cfg(not(platfor="windows"))
let _unused : Unit = {
  ignore(@os_error.check_errno)
  ignore(@os_string.encode)
}

///|
pub fn PipeRead::close(self : PipeRead) -> Unit {
  self.io.close()
}

///|
pub fn PipeWrite::close(self : PipeWrite) -> Unit {
  let PipeWrite(io) = self
  io.close()
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
pub impl @io.Reader for PipeRead with _direct_read(self, buf, offset~, max_len~) {
  self.io.read(buf, offset~, len=max_len, context="@pipe.PipeRead::read()")
}

///|
pub impl @io.Reader for PipeRead with _get_internal_buffer(self) {
  self.read_buf
}

///|
pub impl @io.Writer for PipeWrite with write_once(self, buf, offset~, len~) {
  let PipeWrite(io) = self
  io.write(buf, offset~, len~, context="@pipe.PipeRead::write()")
}
