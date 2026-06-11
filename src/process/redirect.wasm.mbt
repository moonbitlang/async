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
struct ReadFromProcess {
  io : @event_loop.IoHandle
  read_buf : @io.ReaderBuffer
}

///|
priv struct TempPipeWrite {
  pipe : @event_loop.IoHandle
  mut closed : Bool
}

///|
trait ProcessInput {
  fn fd(Self) -> @fd_util.Fd
  fn after_spawn(Self) -> Unit = _
}

///|
impl ProcessInput with fn after_spawn(_) {
  ()
}

///|
trait ProcessOutput {
  fn fd(Self) -> @fd_util.Fd
  fn after_spawn(Self) -> Unit = _
}

///|
impl ProcessOutput with fn after_spawn(_) {
  ()
}

///|
pub fn read_from_process() -> (ReadFromProcess, &ProcessOutput) raise {
  let context = "@process.read_from_process()"
  let (r, w) = @fd_util.pipe(
    read_end_is_async=true,
    write_end_is_async=false,
    context~,
  )
  let r = @event_loop.IoHandle::from_fd(r, kind=Pipe)
  let w = @event_loop.IoHandle::from_fd(w, kind=Pipe, is_async=false)
  (
    { io: r, read_buf: @io.ReaderBuffer::new() },
    TempPipeWrite::{ pipe: w, closed: false },
  )
}

///|
pub fn ReadFromProcess::close(self : ReadFromProcess) -> Unit {
  self.io.close()
}

///|
pub impl @io.Reader for ReadFromProcess with fn _get_internal_buffer(self) {
  self.read_buf
}

///|
pub impl @io.Reader for ReadFromProcess with fn _direct_read(
  self,
  buf,
  offset~,
  max_len~,
) {
  self.io.read(
    buf,
    offset~,
    len=max_len,
    context="@process.ReadFromProcess::read()",
  )
}

///|
impl ProcessOutput for TempPipeWrite with fn fd(self) {
  self.pipe.fd()
}

///|
impl ProcessOutput for TempPipeWrite with fn after_spawn(self) {
  if !self.closed {
    self.closed = true
    self.pipe.close()
  }
}
