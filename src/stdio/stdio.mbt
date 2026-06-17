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
struct Input {
  io : Result[@event_loop.IoHandle, Error]
  read_buf : @io.ReaderBuffer
}

///|
/// Return the file descriptor of an input channel.
///
/// If the initialization of the input channel failed,
/// for example when `stdin` does not exist (Windows) or is not a valid fd (Unix-like),
/// This method will fail with error.
/// So `.fd()` can be used as a way to tell if `stdin` is valid.
pub fn Input::fd(self : Input) -> @fd_util.Fd raise {
  self.io.unwrap_or_error().fd()
}

///|
pub impl @io.Reader for Input with fn _direct_read(self, buf, offset~, max_len~) {
  self.io
  .unwrap_or_error()
  .read(buf, offset~, len=max_len, context="@stdio.Input::read()")
}

///|
pub impl @io.Reader for Input with fn _get_internal_buffer(self) {
  self.read_buf
}

///|
struct Output(Result[@event_loop.IoHandle, Error])

///|
/// Return the file descriptor of an output channel.
///
/// If the initialization of the output channel failed,
/// for example when `stdout` does not exist (Windows) or is not a valid fd (Unix-like),
/// This method will fail with error.
/// So `.fd()` can be used as a way to tell if `stdout`/`stderr` is valid.
pub fn Output::fd(self : Output) -> @fd_util.Fd raise {
  self.0.unwrap_or_error().fd()
}

///|
pub impl @io.Writer for Output with fn write_once(self, buf, offset~, len~) {
  self.0
  .unwrap_or_error()
  .write(buf, offset~, len~, context="@stdio.Output::write()")
}

///|
/// The standard input channel.
///
/// If `stdin` does not exist or is invalid,
/// all operations on `stdin` will immediately fail with error.
pub let stdin : Input = {
  io: @event_loop.stdin,
  read_buf: @io.ReaderBuffer::new(),
}

///|
/// The standard output channel.
///
/// If `stdout` does not exist or is invalid,
/// all operations on `stdout` will immediately fail with error.
pub let stdout : Output = @event_loop.stdout

///|
/// The standard error channel.
///
/// If `stderr` does not exist or is invalid,
/// all operations on `stderr` will immediately fail with error.
pub let stderr : Output = @event_loop.stderr
