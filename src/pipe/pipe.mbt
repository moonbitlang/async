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

/// The read end of a pipe.
/// 
/// A `PipeRead` represents the readable end of a pipe that supports
/// asynchronous reading operations through the `@io.Reader` trait.
/// It wraps a file descriptor and provides methods for reading data
/// from the pipe in an async-compatible manner.
struct PipeRead(Int)

/// Get the file descriptor of the pipe read end.
/// 
/// # Arguments
/// 
/// * `self` - The pipe read end
/// 
/// # Returns
/// 
/// The file descriptor as an integer
pub fn PipeRead::fd(self : PipeRead) -> Int {
  let PipeRead(fd) = self
  fd
}

/// The write end of a pipe.
/// 
/// A `PipeWrite` represents the writable end of a pipe that supports
/// asynchronous writing operations through the `@io.Writer` trait.
/// It wraps a file descriptor and provides methods for writing data
/// to the pipe in an async-compatible manner.
struct PipeWrite(Int)

/// Get the file descriptor of the pipe write end.
/// 
/// # Arguments
/// 
/// * `self` - The pipe write end
/// 
/// # Returns
/// 
/// The file descriptor as an integer
pub fn PipeWrite::fd(self : PipeWrite) -> Int {
  let PipeWrite(fd) = self
  fd
}

/// Create a pipe using the `pipe(2)` system call.
/// 
/// This function creates a new pipe and returns both the read and write ends.
/// Both ends are automatically set to non-blocking mode for async compatibility.
/// 
/// # Returns
/// 
/// A tuple containing `(PipeRead, PipeWrite)` representing the read and write
/// ends of the pipe respectively.
/// 
/// # Raises
/// 
/// This function may raise an exception if the underlying `pipe(2)` system call
/// fails or if setting the file descriptors to non-blocking mode fails.
pub fn pipe() -> (PipeRead, PipeWrite) raise {
  let (r, w) = @fd_util.pipe("@pipe.pipe()")
  @fd_util.set_nonblocking(r, context="@pipe.pipe()")
  @fd_util.set_nonblocking(w, context="@pipe.pipe()")
  (PipeRead(r), PipeWrite(w))
}

/// The standard input treated as a pipe.
/// 
/// This provides access to stdin as a `PipeRead` for async operations.
/// Using this value will result in standard input being set to non-blocking mode.
/// The `@async.with_event_loop` function will reset standard input back to its
/// original state on exit.
/// 
/// # Note
/// 
/// This is only set to non-blocking if stdin was originally in blocking mode.
/// Event loop hooks are registered to restore the original state when the
/// event loop exits.
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

/// The standard output treated as a pipe.
/// 
/// This provides access to stdout as a `PipeWrite` for async operations.
/// Using this value will result in standard output being set to non-blocking mode.
/// The `@async.with_event_loop` function will reset standard output back to its
/// original state on exit.
/// 
/// # Note
/// 
/// This is only set to non-blocking if stdout was originally in blocking mode.
/// Event loop hooks are registered to restore the original state when the
/// event loop exits.
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

/// The standard error treated as a pipe.
/// 
/// This provides access to stderr as a `PipeWrite` for async operations.
/// Using this value will result in standard error being set to non-blocking mode.
/// The `@async.with_event_loop` function will reset standard error back to its
/// original state on exit.
/// 
/// # Note
/// 
/// This is only set to non-blocking if stderr was originally in blocking mode.
/// Event loop hooks are registered to restore the original state when the
/// event loop exits.
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

/// Close the read end of a pipe.
/// 
/// This function closes the file descriptor associated with the pipe read end
/// and removes it from the event loop monitoring.
/// 
/// # Arguments
/// 
/// * `self` - The pipe read end to close
pub fn PipeRead::close(self : PipeRead) -> Unit {
  let PipeRead(fd) = self
  @event_loop.close_fd(fd)
}

/// Close the write end of a pipe.
/// 
/// This function closes the file descriptor associated with the pipe write end
/// and removes it from the event loop monitoring.
/// 
/// # Arguments
/// 
/// * `self` - The pipe write end to close
pub fn PipeWrite::close(self : PipeWrite) -> Unit {
  let PipeWrite(fd) = self
  @event_loop.close_fd(fd)
}

/// Implementation of the `@io.Reader` trait for `PipeRead`.
/// 
/// This provides async reading capabilities for pipe read ends using the `read(2)` system call.
/// The implementation supports partial reads and will only read as much data as is immediately
/// available, making it suitable for async I/O operations.
/// 
/// # Parameters
/// 
/// * `self` - The pipe read end
/// * `buf` - The buffer to read data into
/// * `offset` - Optional starting offset in the buffer (default: 0)
/// * `max_len` - Optional maximum number of bytes to read (default: remaining buffer space)
/// 
/// # Returns
/// 
/// The number of bytes actually read into the buffer.
/// 
/// # Note
/// 
/// At most one task can read from a pipe at any time. To allow multiple readers,
/// use a worker task for reading and use `@async.Queue` to distribute the data.
pub impl @io.Reader for PipeRead with read(
  self,
  buf,
  offset? = 0,
  max_len? = buf.length() - offset,
) {
  let PipeRead(fd) = self
  @event_loop.read(
    fd,
    buf,
    offset~,
    len=max_len,
    can_poll=true,
    context="@pipe.PipeRead::read()",
  )
}

/// Implementation of the `@io.Writer` trait for `PipeWrite`.
/// 
/// This provides async writing capabilities for pipe write ends using the `write(2)` system call.
/// The implementation supports partial writes and will write as much data as the pipe can
/// immediately accept, making it suitable for async I/O operations.
/// 
/// # Parameters
/// 
/// * `self` - The pipe write end
/// * `buf` - The buffer containing data to write
/// * `offset` - The starting offset in the buffer
/// * `len` - The number of bytes to write
/// 
/// # Returns
/// 
/// The number of bytes actually written to the pipe.
pub impl @io.Writer for PipeWrite with write_once(self, buf, offset~, len~) {
  let PipeWrite(fd) = self
  @event_loop.write(
    fd,
    buf,
    offset~,
    len~,
    can_poll=true,
    context="@pipe.PipeWrite::write()",
  )
}
