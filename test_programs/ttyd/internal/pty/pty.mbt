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
/// A child process running on a fresh controlling terminal: a Unix PTY or a
/// Windows pseudo console. The child's standard handles are not the
/// terminal; it opens the terminal itself (`/dev/tty`, `CONIN$`/`CONOUT$`).
///
/// What is written to a `Pty` is typed into the terminal, and what is read
/// from it is what the terminal displays. On Windows the latter is a rendering
/// of the screen, so it carries VT sequences instead of the child's exact bytes.
struct Pty {
  input : @raw_fd.RawFdStream
  output : @raw_fd.RawFdStream
  handle : Handle
  mut closed : Bool
}

///|
/// Runs `path`, without arguments, on a new `rows`×`cols` terminal. The child
/// inherits the current environment, overridden by `extra_env`.
pub async fn spawn(
  path : StringView,
  rows~ : Int32 = 24,
  cols~ : Int32 = 80,
  extra_env~ : Map[String, String] = Map([]),
) -> Pty {
  let env = @env.get_env_vars()
  for key, value in extra_env {
    env[key] = value
  }
  let env = env.to_array().map(entry => @utf8.encode("\{entry.0}=\{entry.1}"))
  let handle = Handle::spawn(
    @utf8.encode(path),
    FixedArray::from_array(env),
    rows,
    cols,
  )
  let error = handle.error()
  if error != 0 {
    handle.close()
    raise @os_error.OSError(error, context="@pty.spawn()")
  }
  let input = {
    errdefer handle.close()
    @raw_fd.RawFdStream(handle.take_input())
  }
  let output = {
    errdefer {
      input.close()
      handle.close()
    }
    @raw_fd.RawFdStream(handle.take_output())
  }
  { input, output, handle, closed: false, }
}

///|
/// Waits for the child to exit, with the result of `@process.wait_pid`.
pub async fn Pty::wait(self : Pty) -> Int32 {
  @process.wait_pid(self.handle.pid())
}

///|
pub fn Pty::resize(
  self : Pty,
  rows~ : Int32,
  cols~ : Int32,
) -> Unit raise @os_error.OSError {
  let error = self.handle.resize(rows, cols)
  if error != 0 {
    raise @os_error.OSError(error, context="@pty.Pty::resize()")
  }
}

///|
/// Closes the terminal, which kills the child if it is still running. A
/// child that was not waited for is not reaped.
pub fn Pty::close(self : Pty) -> Unit {
  guard !self.closed else { return }
  self.closed = true
  // Our end of the output goes first: before Windows 11 24H2, closing the
  // pseudo console waits for its output to be drained. On Unix, the terminal
  // hangs up, sending SIGHUP, only if the master closes while a slave is
  // still open, so both master descriptors go before the slave anchor.
  self.output.close()
  self.input.close()
  self.handle.close()
}

///|
pub impl @io.Reader for Pty with fn _get_internal_buffer(self) {
  @io.Reader::_get_internal_buffer(self.output)
}

///|
pub impl @io.Reader for Pty with fn _direct_read(self, buf, offset~, max_len~) {
  @io.Reader::_direct_read(self.output, buf, offset~, max_len~)
}

///|
pub extend Pty with @io.Reader::{read_some, read_exactly}

///|
pub impl @io.Writer for Pty with fn write_once(self, buf, offset~, len~) {
  self.input.write_once(buf, offset~, len~)
}

///|
pub extend Pty with @io.Writer::{write}

///|
#deprecated
#doc(hidden)
pub extend Pty with @io.Reader::{
  read,
  drop,
  read_all,
  read_until,
  _direct_read,
  _get_internal_buffer,
}

///|
#deprecated
#doc(hidden)
pub extend Pty with @io.Writer::{write_once, write_reader}

///|
/// The C-side state of a terminal and its child. See stub.c.
#external
priv type Handle

///|
#borrow(path, env)
extern "C" fn Handle::spawn(
  path : Bytes,
  env : FixedArray[Bytes],
  rows : Int32,
  cols : Int32,
) -> Handle = "moonbitlang_async_pty_spawn"

///|
extern "C" fn Handle::error(self : Handle) -> Int32 = "moonbitlang_async_pty_error"

///|
extern "C" fn Handle::pid(self : Handle) -> Int32 = "moonbitlang_async_pty_pid"

///|
/// Transfers ownership of the terminal's input to the caller.
extern "C" fn Handle::take_input(self : Handle) -> @types.Fd = "moonbitlang_async_pty_take_input"

///|
/// Transfers ownership of the terminal's output to the caller.
extern "C" fn Handle::take_output(self : Handle) -> @types.Fd = "moonbitlang_async_pty_take_output"

///|
extern "C" fn Handle::resize(
  self : Handle,
  rows : Int32,
  cols : Int32,
) -> Int32 = "moonbitlang_async_pty_resize"

///|
/// Closes the terminal, which must not be used afterwards, and frees `self`.
extern "C" fn Handle::close(self : Handle) -> Unit = "moonbitlang_async_pty_close"
