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
/// A temporary pipe used to read output from a spawned process
struct ReadFromProcess {
  io : @event_loop.IoHandle
  read_buf : @io.ReaderBuffer
}

///|
/// A temporary pipe used to write data to a spawned process
struct WriteToProcess(@event_loop.IoHandle)

///|
/// Create a temporary pipe for reading from stdout/stderr of a process.
/// The return value is a pair `(r, w)`,
/// where `r` is a temporary pipe that can be used to read process output,
/// and `w` should be passed to `@process.run`, `@process.spawn` etc.
///
/// `w` is temporary: it can only be passed to one `@process.run` call.
/// However, it is safe to pass `w` to both `stdout` and `stderr` of the same process.
///
/// If `shared` is `false` (the default), the created pipe is unique.
/// In this case, `w` can only be passed to one child process
/// (but it is ok to pass `w` to both stdout and stderr of the same process),
/// and `w` will be closed automatically after the child process started.
///
/// If `shared` is `true`, the created pipe is shared:
/// `w` can be passed to multiple children process to merge and collect their output.
/// In this case, `w` should be closed manually via `w.close()`
/// after being passed to the last child process.
/// Note that `w` can be closed immediately after the last child process *started*,
/// there is no need to wait for the termination of the child process.
/// If you forgot to close `w` or close it too late,
/// the read end `r` will fail to observe EOF from children process.
pub fn read_from_process(
  shared? : Bool = false,
) -> (ReadFromProcess, &ProcessOutput) raise {
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
    TempPipeWrite::{ pipe: w, shared, closed: false },
  )
}

///|
/// Create a temporary pipe for writing to stdin of a process.
/// The return value is a pair `(r, w)`,
/// where `w` is a temporary pipe that can be used to write to process output,
/// and `r` should be passed to `@process.run`.
pub fn write_to_process() -> (&ProcessInput, WriteToProcess) raise {
  let context = "@process.write_to_process()"
  let (r, w) = @fd_util.pipe(
    read_end_is_async=false,
    write_end_is_async=true,
    context~,
  )
  let r = @event_loop.IoHandle::from_fd(r, kind=Pipe, is_async=false)
  let w = @event_loop.IoHandle::from_fd(w, kind=Pipe)
  (TempPipeRead::{ pipe: r, closed: false }, w)
}

///|
/// Create a temporary pipe for connecting the output of
/// one child process to the input of another child process.
pub fn pipe() -> (&ProcessInput, &ProcessOutput) raise {
  let context = "@process.pipe()"
  let (r, w) = @fd_util.pipe(
    read_end_is_async=false,
    write_end_is_async=false,
    context~,
  )
  let r = @event_loop.IoHandle::from_fd(r, kind=Pipe, is_async=false)
  let w = @event_loop.IoHandle::from_fd(w, kind=Pipe, is_async=false)
  (
    TempPipeRead::{ pipe: r, closed: false },
    TempPipeWrite::{ pipe: w, shared: false, closed: false },
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
pub fn WriteToProcess::close(self : WriteToProcess) -> Unit {
  let WriteToProcess(io) = self
  io.close()
}

///|
pub impl @io.Writer for WriteToProcess with fn write_once(
  self,
  buf,
  offset~,
  len~,
) {
  let WriteToProcess(io) = self
  io.write(buf, offset~, len~, context="@process.WriteToProcess::write()")
}

///|
fn @fs.CreateMode::to_int(self : @fs.CreateMode) -> Int = "%identity"

///|
/// Redirect the output of a process to the file at `path`.
/// An output channel that should be passed to child process will be returned.
///
/// The meaning of `append`, `create_mode` and `permission` is the same as `@fs.open`,
/// see the document of `@fs.open` for more details.
///
/// If `shared` is `false` (the default), the returned channel `w` is unique.
/// In this case, `w` can only be passed to one child process
/// (but it is ok to pass `w` to both stdout and stderr of the same process),
/// and `w` will be closed automatically after the child process started.
///
/// If `shared` is `true`, the returned channel `w` is shared:
/// it can be passed to multiple children process to merge and collect their output.
/// In this case, `w` should be closed manually via `w.close()`
/// after being passed to the last child process.
/// Note that `w` can be closed immediately after the last child process *started*,
/// there is no need to wait for the termination of the child process.
pub async fn redirect_to_file(
  path : String,
  append? : Bool = false,
  create_mode? : @fs.CreateMode = CreateOrTruncate,
  permission? : Int = 0o644,
  shared? : Bool = false,
) -> &ProcessOutput {
  let (file, _) = @event_loop.open(
    path,
    1, // write only
    create=create_mode.to_int(),
    append~,
    sync=0,
    mode=permission,
    context="@process.redirect_to_file()",
  )
  RedirectToFile::{ io: file, shared, closed: false }
}

///|
/// Redirect the content of a file at `path` to the stdin of a process.
pub async fn redirect_from_file(path : String) -> &ProcessInput {
  let (file, _) = @event_loop.open(
    path,
    0, // read only
    create=0, // `OpenExisting`
    append=false,
    sync=0,
    mode=0,
    context="@process.redirect_from_file()",
  )
  RedirectToFile::{ io: file, shared: false, closed: false }
}

///|
/// An entity that can be used to redirect stdin of a process
trait ProcessInput {
  fn fd(Self) -> @fd_util.Fd raise
  fn after_spawn(Self) -> Unit = _
}

///|
impl ProcessInput with fn after_spawn(_) {
  ()
}

///|
#deprecated("use `@process.write_to_process()` or `@process.pipe()` instead")
pub impl ProcessInput for @pipe.PipeRead

///|
pub impl ProcessInput for @pipe.PipeRead with fn fd(self) {
  self.fd()
}

///|
pub impl ProcessInput for @stdio.Input with fn fd(self) {
  self.fd()
}

///|
/// An entity that can be used to redirect stdout/stderr of a process
trait ProcessOutput {
  fn fd(Self) -> @fd_util.Fd raise
  /// Close the output channel.
  /// May be called automatically via `after_spawn`, or manually via `.close()`
  fn do_close(Self) -> Unit = _
  fn after_spawn(Self) -> Unit = _
}

///|
/// Close a shared channel for redirecting process output.
/// Once closed, the channel can no longer be passed to child process.
/// Note that unique channels are automatically closed after being passed to child process,
/// so there is no need to manually call `.close()` on a unique channel.
/// See `@process.read_from_process` for more details.
pub fn &ProcessOutput::close(self : &ProcessOutput) -> Unit {
  self.do_close()
}

///|
impl ProcessOutput with fn do_close(_) {
  ()
}

///|
impl ProcessOutput with fn after_spawn(_) {
  ()
}

///|
#deprecated("use `@process.read_from_process(shared~)` or `@process.pipe()` instead")
pub impl ProcessOutput for @pipe.PipeWrite

///|
pub impl ProcessOutput for @pipe.PipeWrite with fn fd(self) {
  self.fd()
}

///|
pub impl ProcessOutput for @stdio.Output with fn fd(self) {
  self.fd()
}

///|
priv struct TempPipeRead {
  pipe : @event_loop.IoHandle
  mut closed : Bool
}

///|
priv struct TempPipeWrite {
  pipe : @event_loop.IoHandle
  shared : Bool
  mut closed : Bool
}

///|
impl ProcessOutput for TempPipeWrite with fn fd(self) {
  self.pipe.fd()
}

///|
impl ProcessOutput for TempPipeWrite with fn do_close(self) {
  if !self.closed {
    self.closed = true
    self.pipe.close()
  }
}

///|
impl ProcessOutput for TempPipeWrite with fn after_spawn(self) {
  if !self.shared {
    ProcessOutput::do_close(self)
  }
}

///|
impl ProcessInput for TempPipeRead with fn fd(self) {
  self.pipe.fd()
}

///|
impl ProcessInput for TempPipeRead with fn after_spawn(self) {
  if !self.closed {
    self.closed = true
    self.pipe.close()
  }
}

///|
priv struct RedirectToFile {
  io : @event_loop.IoHandle
  shared : Bool
  mut closed : Bool
}

///|
impl ProcessOutput for RedirectToFile with fn fd(self) {
  self.io.fd()
}

///|
impl ProcessOutput for RedirectToFile with fn do_close(self) {
  if !self.closed {
    self.closed = true
    self.io.close()
  }
}

///|
impl ProcessOutput for RedirectToFile with fn after_spawn(self) {
  if !self.shared {
    ProcessOutput::do_close(self)
  }
}

///|
impl ProcessInput for RedirectToFile with fn fd(self) {
  self.io.fd()
}

///|
impl ProcessInput for RedirectToFile with fn after_spawn(self) {
  if !self.closed {
    self.closed = true
    self.io.close()
  }
}
