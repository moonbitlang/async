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
  let (r, w) = @fd_util.pipe("@pipe.pipe()")
  @fd_util.set_nonblocking(r, context="@pipe.pipe()")
  @fd_util.set_nonblocking(w, context="@pipe.pipe()")
  (PipeRead(r), PipeWrite(w))
}

///|
/// The standard input treated as a pipe.
/// Using this value will result in standard input being set to non-blocking mode.
/// `@async.with_event_loop` will reset standard input
/// back to its original state on exit.
pub let stdin : PipeRead = {
  if get_blocking(0) > 0 {
    fn init() {
      @fd_util.set_nonblocking(0, context="initialize `@pipe.stdin`") catch {
        _ => ()
      }
    }

    fn exit() {
      @fd_util.set_nonblocking(0, context="restore `@pipe.stdin`") catch {
        _ => ()
      }
    }

    @event_loop.register_hook(init~, exit~)
  }
  PipeRead(0)
}

///|
/// The standard output treated as a pipe.
/// Using this value will result in standard output being set to non-blocking mode.
/// `@async.with_event_loop` will reset standard output
/// back to its original state on exit.
pub let stdout : PipeWrite = {
  if get_blocking(1) > 0 {
    fn init() {
      @fd_util.set_nonblocking(1, context="initialize `@pipe.stdout`") catch {
        _ => ()
      }
    }

    fn exit() {
      @fd_util.set_nonblocking(1, context="restore `@pipe.stdout`") catch {
        _ => ()
      }
    }

    @event_loop.register_hook(init~, exit~)
  }
  PipeWrite(1)
}

///|
/// The standard error treated as a pipe.
/// Using this value will result in standard error being set to non-blocking mode.
/// `@async.with_event_loop` will reset standard error
/// back to its original state on exit.
pub let stderr : PipeWrite = {
  if get_blocking(2) > 0 {
    fn init() {
      @fd_util.set_nonblocking(2, context="initialize `@pipe.stderr`") catch {
        _ => ()
      }
    }

    fn exit() {
      @fd_util.set_nonblocking(2, context="restore `@pipe.stderr`") catch {
        _ => ()
      }
    }

    @event_loop.register_hook(init~, exit~)
  }
  PipeWrite(2)
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
///
/// At most one task can read from a pipe at any time.
/// To allow multiple reader,
/// use a worker task for reading and use `@async.Queue` to distribute the data.
pub impl @io.Reader for PipeRead with read(
  self,
  buf,
  offset? = 0,
  max_len? = buf.length() - offset,
) {
  let PipeRead(fd) = self
  @event_loop.perform_job(
    Read(fd~, buf~, offset~, len=max_len, can_poll=true),
    context="@pipe.PipeRead::read()",
  )
}

///|
pub impl @io.Writer for PipeWrite with write_once(self, buf, offset~, len~) {
  let PipeWrite(fd) = self
  @event_loop.perform_job(
    Write(fd~, buf~, offset~, len~, can_poll=true),
    context="@pipe.PipeRead::write()",
  )
}
