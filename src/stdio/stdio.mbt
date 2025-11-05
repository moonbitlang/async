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
using @fd_util {type FileKind}

///|
struct Input {
  io : @event_loop.IOHandle
  kind : FileKind
}

///|
pub fn Input::fd(self : Input) -> Int {
  self.io.fd()
}

///|
pub impl @io.Reader for Input with read(
  self,
  buf,
  offset? = 0,
  max_len? = buf.length() - offset,
) {
  self.io.read(buf, offset~, len=max_len, context="@stdio.Input::read()")
}

///|
struct Output {
  io : @event_loop.IOHandle
  kind : FileKind
}

///|
pub fn Output::fd(self : Output) -> Int {
  self.io.fd()
}

///|
pub impl @io.Writer for Output with write_once(self, buf, offset~, len~) {
  self.io.write(buf, offset~, len~, context="@fs.File::write()")
}

///|
fn setup_nonblocking_fd(
  fd : Int,
  context~ : String,
  restore_context~ : String,
) -> FileKind raise {
  let kind = @fd_util.fstat_sync(fd, context~).kind()
  if kind.can_poll() && not(@fd_util.fd_is_nonblocking(fd, context~)) {
    fn init() raise {
      @fd_util.set_nonblocking(fd, context~)
    }

    fn exit() raise {
      @fd_util.set_nonblocking(fd, context=restore_context)
    }

    @event_loop.register_hook(init~, exit~)
  }
  kind
}

///|
/// The standard input channel.
/// Using this value will result in standard input being set to non-blocking mode.
/// The standard input will be reset to its original state after the program exits.
pub let stdin : Input = {
  let context = "initialize `stdin`"
  try {
    let kind = setup_nonblocking_fd(
      0,
      context~,
      restore_context="restore `stdin`",
    )
    { io: @event_loop.IOHandle::from_fd(0, kind~), kind }
  } catch {
    err => abort(err.to_string())
  }
}

///|
/// The standard output channel.
/// Using this value will result in standard output being set to non-blocking mode.
/// The standard output will be reset to its original state after the program exits.
pub let stdout : Output = {
  let context = "initialize `stdout`"
  try {
    let kind = setup_nonblocking_fd(
      1,
      context~,
      restore_context="restore `stdout`",
    )
    { io: @event_loop.IOHandle::from_fd(1, kind~), kind }
  } catch {
    err => abort(err.to_string())
  }
}

///|
/// The standard error channel.
/// Using this value will result in standard error being set to non-blocking mode.
/// The standard error will be reset to its original state after the program exits.
pub let stderr : Output = {
  let context = "initialize `stderr`"
  try {
    let kind = setup_nonblocking_fd(
      2,
      context~,
      restore_context="restore `stderr`",
    )
    { io: @event_loop.IOHandle::from_fd(2, kind~), kind }
  } catch {
    err => abort(err.to_string())
  }
}
