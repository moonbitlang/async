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
/// An entity that can be used to redirect stdin of a process
trait ProcessInput {
  async fn fd(Self) -> @fd_util.Fd
  // invoked when `spawn` succeeded using this channel
  fn on_success(Self) -> Unit
  // invoked when `spawn` failed using this channel
  fn on_failure(Self) -> Unit
}

///|
/// An entity that can be used to redirect stdout/stderr of a process
trait ProcessOutput {
  async fn fd(Self) -> @fd_util.Fd
  fn is_shared(Self) -> Bool
  // invoked when `spawn` succeeded using this channel
  fn on_success(Self) -> Unit
  // invoked when `spawn` failed using this channel
  fn on_failure(Self) -> Unit
}

///|
#deprecated("use `@process.write_to_process()` or `@process.pipe()` instead")
pub impl ProcessInput for @pipe.PipeRead

///|
pub impl ProcessInput for @pipe.PipeRead with fn fd(self) {
  self.fd()
}

///|
pub impl ProcessInput for @pipe.PipeRead with fn on_success(_) {

}

///|
pub impl ProcessInput for @pipe.PipeRead with fn on_failure(_) {

}

///|
#deprecated("use `@process.read_from_process(shared~)` or `@process.pipe()` instead")
pub impl ProcessOutput for @pipe.PipeWrite

///|
pub impl ProcessOutput for @pipe.PipeWrite with fn fd(self) {
  self.fd()
}

///|
pub impl ProcessOutput for @pipe.PipeWrite with fn is_shared(_) {
  false
}

///|
pub impl ProcessOutput for @pipe.PipeWrite with fn on_success(_) {

}

///|
pub impl ProcessOutput for @pipe.PipeWrite with fn on_failure(_) {

}

///|
pub impl ProcessInput for @stdio.Input with fn fd(self) {
  self.fd()
}

///|
pub impl ProcessInput for @stdio.Input with fn on_success(_) {

}

///|
pub impl ProcessInput for @stdio.Input with fn on_failure(_) {

}

///|
pub impl ProcessOutput for @stdio.Output with fn fd(self) {
  self.fd()
}

///|
pub impl ProcessOutput for @stdio.Output with fn is_shared(_) {
  false
}

///|
pub impl ProcessOutput for @stdio.Output with fn on_success(_) {

}

///|
pub impl ProcessOutput for @stdio.Output with fn on_failure(_) {

}

///|
/// Close an input channel that will not be passed to a child process.
/// A channel is closed automatically once it is passed to a child process,
/// so this is only needed when a channel has been created
/// but spawning the process that would consume it fails or is abandoned.
/// Closing is idempotent, and a no-op for channels that only borrow
/// their file descriptor, such as `@stdio.stdin`.
#doc(hidden)
#deprecated
pub fn &ProcessInput::close(self : &ProcessInput) -> Unit {
  self.on_success()
}

///|
/// Close a shared channel for redirecting process output.
/// Once closed, the channel can no longer be passed to child process.
/// Note that unique channels are automatically closed after being passed to child process,
/// so there is no need to manually call `.close()` on a unique channel.
/// See `@process.read_from_process` for more details.
pub fn &ProcessOutput::close(self : &ProcessOutput) -> Unit {
  self.on_success()
}

///|
priv enum TempPipeKind {
  ReadFromProcess
  ReadFromProcessShared
  WriteToProcess
  Pipe
}

///|
priv enum TempPipeEndpoint {
  Uninitialized
  Active(@event_loop.IoHandle)
  Closed
}

///|
priv struct TempPipe {
  mut r : TempPipeEndpoint
  mut w : TempPipeEndpoint
  /// how this pipe is created, for error reporting
  kind : TempPipeKind
  mut waiter : @coroutine.Coroutine?
}

///|
/// A temporary pipe used to read output from a spawned process
struct ReadFromProcess {
  pipe : TempPipe
  read_buf : @io.ReaderBuffer
}

///|
/// A temporary pipe used to write data to a spawned process
struct WriteToProcess(TempPipe)

///|
fn TempPipe::TempPipe(kind : TempPipeKind) -> TempPipe {
  { r: Uninitialized, w: Uninitialized, kind, waiter: None }
}

///|
fn TempPipe::init(self : TempPipe) -> Unit raise {
  let (read_end_is_async, write_end_is_async, context) = match self.kind {
    ReadFromProcess | ReadFromProcessShared =>
      (true, false, "@process.read_from_process()")
    WriteToProcess => (false, true, "@process.write_to_process()")
    Pipe => (false, false, "@process.pipe()")
  }
  if self.waiter is Some(coro) {
    coro.wake()
  }
  let (r, w) = @fd_util.pipe(read_end_is_async~, write_end_is_async~, context~)
  let r = {
    errdefer @fd_util.close(w, kind=Pipe, context~)
    @event_loop.IoHandle::from_fd(r, kind=Pipe, is_async=read_end_is_async)
  }
  let w = @event_loop.IoHandle::from_fd(
    w,
    kind=Pipe,
    is_async=write_end_is_async,
  )
  self.r = Active(r)
  self.w = Active(w)
}

///|
fn TempPipe::close_read(self : TempPipe) -> Unit {
  if self.r is Active(r) {
    r.close()
  }
  self.r = Closed
  if self.waiter is Some(coro) {
    coro.wake()
  }
  if self.w is Uninitialized {
    self.w = Closed
  }
}

///|
fn TempPipe::close_write(self : TempPipe) -> Unit {
  if self.w is Active(w) {
    w.close()
  }
  self.w = Closed
  if self.waiter is Some(coro) {
    coro.wake()
  }
  if self.r is Uninitialized {
    self.r = Closed
  }
}

///|
impl ProcessInput for TempPipe with fn fd(self) {
  match self.r {
    Uninitialized => self.init()
    Active(_) => ()
    Closed => {
      let context = match self.kind {
        ReadFromProcess | ReadFromProcessShared =>
          "@process.read_from_process()"
        WriteToProcess => "@process.write_to_process()"
        Pipe => "@process.pipe()"
      }
      raise @os_error.OSError(@os_error.errno_EPIPE, context~)
    }
  }
  guard! self.r is Active(r)
  r.fd()
}

///|
impl ProcessInput for TempPipe with fn on_success(self) {
  self.close_read()
}

///|
impl ProcessInput for TempPipe with fn on_failure(self) {
  self.close_read()
  if self.kind is Pipe {
    self.close_write()
  }
}

///|
impl ProcessOutput for TempPipe with fn fd(self) {
  match self.w {
    Uninitialized => self.init()
    Active(_) => ()
    Closed => {
      let context = match self.kind {
        ReadFromProcess | ReadFromProcessShared =>
          "@process.read_from_process()"
        WriteToProcess => "@process.write_to_process()"
        Pipe => "@process.pipe()"
      }
      raise @os_error.OSError(@os_error.errno_EPIPE, context~)
    }
  }
  guard! self.w is Active(w)
  w.fd()
}

///|
impl ProcessOutput for TempPipe with fn is_shared(self) {
  self.kind is ReadFromProcessShared
}

///|
impl ProcessOutput for TempPipe with fn on_success(self) {
  self.close_write()
}

///|
impl ProcessOutput for TempPipe with fn on_failure(self) {
  self.close_write()
  if self.kind is Pipe {
    self.close_read()
  }
}

///|
/// Create a temporary pipe for reading from stdout/stderr of a process.
/// The return value is a pair `(r, w)`,
/// where `r` is a temporary pipe that can be used to read process output,
/// and `w` should be passed to `@process.run`, `@process.spawn` etc.
///
/// `w` is temporary: it can only be passed to one `@process.run` call.
/// However, it is safe to pass `w` to both `stdout` and `stderr` of the same process.
///
/// The pipe is lazy initialized: it will only get created
/// after being passed to the first child process.
/// So there will be no resource leak if the pipe never get used.
///
/// If `shared` is `false` (the default), the created pipe is unique.
/// In this case, `w` can only be passed to one child process
/// (but it is ok to pass `w` to both stdout and stderr of the same process),
/// but there is no need to close `w` manually in any circumstance:
/// - `w` is lazy initialized: the pipe will only get created
///   when being passed to the child process.
///   So there will be no resource leak if the pipe never get used.
/// - `w` will be closed automatically after the child process started
///   or if child process spawning failed
///
/// If `shared` is `true`, the created pipe is shared:
/// `w` can be passed to multiple children process to merge and collect their output.
/// In this case, `w` should be closed manually via `w.close()`
/// after being passed to the last child process.
/// Note that `w` should be closed immediately after the last child process *started*,
/// there is no need to wait for the termination of the child process.
/// If you forgot to close `w` or close it too late,
/// the read end `r` will fail to observe EOF from children process.
pub fn read_from_process(
  shared? : Bool = false,
) -> (ReadFromProcess, &ProcessOutput) {
  let pipe = TempPipe(
    if shared {
      ReadFromProcessShared
    } else {
      ReadFromProcess
    },
  )
  ({ pipe, read_buf: @io.ReaderBuffer::new() }, pipe)
}

///|
/// Create a temporary pipe for writing to stdin of a process.
/// The return value is a pair `(r, w)`,
/// where `w` is a temporary pipe that can be used to write to process output,
/// and `r` should be passed to `@process.run
pub fn write_to_process() -> (&ProcessInput, WriteToProcess) {
  let pipe = TempPipe(WriteToProcess)
  (pipe, pipe)
}

///|
/// Create a temporary pipe for connecting the output of
/// one child process to the input of another child process.
/// The two pipe endpoints returned can be passed to only one child process.
///
/// In most cases, there is no need to manually close the pipe:
///
/// - the pipe is lazy initialized. If both ends of pipe are never used,
///   for example the program fail before spawning the first child,
///   the pipe will not get created at all, so there will be no resource leak
/// - when the child process is spawned successfully,
///   it will automatically close the end it receives.
/// - when the child process fail to spawn,
///   *both* ends of pipe will be closed automatically.
///
/// The only case where the pipe need to be closed manually is when the program
/// fail *after* the first child is spawned successfully,
/// but *before* invoking spawning operation on the second child.
/// Users should avoid this pattern and perform necessary initialization
/// before spawning the first child.
pub fn pipe() -> (&ProcessInput, &ProcessOutput) {
  let pipe = TempPipe(Pipe)
  (pipe, pipe)
}

///|
pub fn ReadFromProcess::close(self : ReadFromProcess) -> Unit {
  self.pipe.close_read()
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
  if self.pipe.r is Uninitialized {
    guard! self.pipe.waiter is None
    self.pipe.waiter = Some(@coroutine.current_coroutine())
    defer {
      self.pipe.waiter = None
    }
    @coroutine.suspend()
  }
  guard self.pipe.r is Active(io) else { 0 }
  io.read(buf, offset~, len=max_len, context="@process.ReadFromProcess::read()")
}

///|
pub extend ReadFromProcess with @io.Reader::{
  read,
  drop,
  read_exactly,
  read_some,
  read_all,
  read_until,
}

///|
pub fn WriteToProcess::close(self : WriteToProcess) -> Unit {
  let WriteToProcess(pipe) = self
  pipe.close_write()
}

///|
pub impl @io.Writer for WriteToProcess with fn write_once(
  self,
  buf,
  offset~,
  len~,
) {
  let context = "@process.WriteToProcess::write()"
  let WriteToProcess(pipe) = self
  if pipe.w is Uninitialized {
    guard! pipe.waiter is None
    pipe.waiter = Some(@coroutine.current_coroutine())
    defer {
      pipe.waiter = None
    }
    @coroutine.suspend()
  }
  guard pipe.w is Active(io) else {
    raise @os_error.OSError(@os_error.errno_EPIPE, context~)
  }
  io.write(buf, offset~, len~, context~)
}

///|
pub extend WriteToProcess with @io.Writer::{write_once, write, write_reader}

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
/// but there is no need to manually close `w` in any circumstance:
/// - `w` is lazy initialized: the file will only get opened
///   when being passed to the child process.
///   So there will be no resource leak if the channel never get used.
/// - `w` will be closed automatically after the child process started
///   or if child process spawning failed
///
/// If `shared` is `true`, the returned channel `w` is shared:
/// it can be passed to multiple children process to merge and collect their output.
/// In this case, `w` should be closed manually via `w.close()`
/// after being passed to the last child process.
/// Note that `w` can be closed immediately after the last child process *started*,
/// there is no need to wait for the termination of the child process.
pub fn redirect_to_file(
  path : String,
  append? : Bool = false,
  create_mode? : @fs.CreateMode = CreateOrTruncate,
  permission? : Int = 0o644,
  shared? : Bool = false,
) -> &ProcessOutput {
  let closed = Ref(false)
  let file = @async.Lazy <| () => {
    let context = "@process.redirect_to_file()"
    if closed.val {
      raise @os_error.OSError(@os_error.errno_EPIPE, context~)
    }
    let (file, _) = @event_loop.open(
      path,
      1, // write only
      create=create_mode.to_int(),
      append~,
      sync=0,
      mode=permission,
      context~,
    )
    if closed.val {
      file.close()
      raise @os_error.OSError(@os_error.errno_EPIPE, context~)
    }
    file
  }
  RedirectToFile::{ file, shared, closed }
}

///|
/// Redirect the content of a file at `path` to the stdin of a process.
pub fn redirect_from_file(path : String) -> &ProcessInput {
  let closed = Ref(false)
  let file = @async.Lazy <| () => {
    let context = "@process.redirect_from_file()"
    if closed.val {
      raise @os_error.OSError(@os_error.errno_EPIPE, context~)
    }
    let (file, _) = @event_loop.open(
      path,
      0, // read only
      create=0, // `OpenExisting`
      append=false,
      sync=0,
      mode=0,
      context~,
    )
    if closed.val {
      file.close()
      raise @os_error.OSError(@os_error.errno_EPIPE, context~)
    }
    file
  }
  RedirectToFile::{ file, shared: false, closed }
}

///|
priv struct RedirectToFile {
  file : @async.Lazy[@event_loop.IoHandle]
  shared : Bool
  closed : Ref[Bool]
}

///|
fn RedirectToFile::close(self : RedirectToFile) -> Unit {
  if !self.closed.val {
    self.closed.val = true
    try self.file.try_wait() catch {
      _ => ()
    } noraise {
      Some(file) => file.close()
      None => ()
    }
  }
}

///|
impl ProcessInput for RedirectToFile with fn fd(self) {
  self.file.wait().fd()
}

///|
impl ProcessInput for RedirectToFile with fn on_success(self) {
  self.close()
}

///|
impl ProcessInput for RedirectToFile with fn on_failure(self) {
  self.close()
}

///|
impl ProcessOutput for RedirectToFile with fn fd(self) {
  self.file.wait().fd()
}

///|
impl ProcessOutput for RedirectToFile with fn is_shared(self) {
  self.shared
}

///|
impl ProcessOutput for RedirectToFile with fn on_success(self) {
  self.close()
}

///|
impl ProcessOutput for RedirectToFile with fn on_failure(self) {
  self.close()
}
