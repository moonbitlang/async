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
/// Gets the current environment variables as an array of byte strings.
/// This is used internally to inherit environment variables from the parent process.
extern "C" fn get_curr_env() -> FixedArray[Bytes?] = "moonbitlang_async_get_curr_env"

///|
/// The current environment variables inherited from the parent process.
let curr_env : FixedArray[Bytes?] = get_curr_env()

///|
/// Terminates a process with the given process ID.
/// This function is used internally for cleanup when processes are cancelled.
extern "C" fn terminate_process(pid : Int) = "moonbitlang_async_terminate_process"

///|
/// Gets the exit code result of a completed process.
/// Returns 0 on success, negative value on error.
#borrow(out)
extern "C" fn get_process_result(pid : Int, out : Ref[Int]) -> Int = "moonbitlang_async_get_process_result"

///|
/// Internal function to spawn a new process asynchronously.
/// This is the core implementation used by both `run` and `spawn_orphan`.
/// 
/// The function handles UTF-8 encoding of command and arguments,
/// environment variable setup, and I/O redirection.
async fn spawn(
  cmd : String,
  args : Array[String],
  extra_env~ : Map[String, String],
  inherit_env~ : Bool,
  stdin~ : &ProcessInput?,
  stdout~ : &ProcessOutput?,
  stderr~ : &ProcessOutput?,
  cwd~ : String?,
  context~ : String,
) -> Int {
  let cmd = @encoding/utf8.encode(cmd)
  let argv = FixedArray::make(args.length() + 2, None)
  let cwd = match cwd {
    None => None
    Some(cwd) => Some(@encoding/utf8.encode(cwd))
  }
  argv[0] = Some(cmd)
  for i in 0..<args.length() {
    argv[i + 1] = Some(@encoding/utf8.encode(args[i]))
  }
  defer {
    if stdin is Some(p) {
      p.after_spawn()
    }
    if stdout is Some(p) {
      p.after_spawn()
    }
    if stderr is Some(p) {
      p.after_spawn()
    }
  }
  let stdin = match stdin {
    Some(pipe) => {
      @fd_util.set_blocking(pipe.fd(), context~)
      pipe.fd()
    }
    None => -1
  }
  let stdout = match stdout {
    Some(pipe) => {
      @fd_util.set_blocking(pipe.fd(), context~)
      pipe.fd()
    }
    None => -1
  }
  let stderr = match stderr {
    Some(pipe) => {
      @fd_util.set_blocking(pipe.fd(), context~)
      pipe.fd()
    }
    None => -1
  }
  let extra_count = extra_env.length()
  let env = match (inherit_env, extra_count) {
    (true, 0) => curr_env
    (false, 0) => [None]
    (_, n) => {
      let curr_env = if inherit_env { curr_env } else { [None] }
      let envp = FixedArray::make(n + curr_env.length(), None)
      let mut i = 0
      for k, v in extra_env {
        envp[i] = Some(@encoding/utf8.encode("\{k}=\{v}"))
        i = i + 1
      }
      curr_env.blit_to(envp, src_offset=0, dst_offset=i, len=curr_env.length())
      envp
    }
  }
  @event_loop.spawn(cmd, argv, env~, stdin~, stdout~, stderr~, cwd~, context~)
}

///|
/// Execute a system process with command `cmd`,
/// and provide `args` as extra arguments to `cmd.
/// Both `cmd` and elements of `args` are encoded using UTF8.
/// The process ID of the spawned process will be returned.
///
/// The spawned process would be *orphan*, meaning that it will
/// keep running until completion or explicitly terminated,
/// even if the task that calls `spawn_orphan` is cancelled.
/// Users are recommended to use `@process.run` whenever possible,
/// because `@process.run` has better structured concurrency integration.
/// `spawn_orphan` should only be used when:
///
/// - the process is intended to be orphan,
///   i.e. keep running after parent process terminates
/// - operations on the process ID is needed, such as sending signals to the child process
///
/// The meaning of the arguments is the same as `@process.run`,
/// see `@process.run` for more details.
pub async fn spawn_orphan(
  cmd : String,
  args : Array[String],
  extra_env? : Map[String, String] = {},
  inherit_env? : Bool = true,
  stdin? : &ProcessInput,
  stdout? : &ProcessOutput,
  stderr? : &ProcessOutput,
  cwd? : String,
) -> Int {
  spawn(
    cmd,
    args,
    extra_env~,
    inherit_env~,
    stdin~,
    stdout~,
    stderr~,
    cwd~,
    context="@process.spawn_orphan()",
  )
}

///|
/// Wait for the process with specfic ID to terminate,
/// and return the exit code of the process.
pub async fn wait_pid(pid : Int) -> Int {
  let context = "@process.wait_pid()"
  @event_loop.wait_pid(pid)
  let out = @ref.new(0)
  let ret = get_process_result(pid, out)
  if ret < 0 {
    @os_error.check_errno(context)
  }
  out.val
}

///|
/// Execute a system process with command `cmd`,
/// and provide `args` as extra arguments to `cmd.
/// Both `cmd` and elements of `args` are encoded using UTF8.
///
/// `run` will block until the new process terminates,
/// and returns the exit status of the process.
/// If current task is cancelled while blocking,
/// the spawned process will be terminated via `SIGTERM`.
/// To run the process in background, use `@async.spawn` or `@async.spawn_bg`.
///
/// If `inherit_env` is `true` (`true` by default),
/// the new process will inherit environment variables of current process.
///
/// `extra_env`, if present, will set extra environment variables for the new process
/// (in addition to those inherited ones, if `inherit_env` is `true`).
/// Keys and values of `extra_env` are encoded using UTF8.
///
/// The standard IO of the new process will be redirected to
/// `stdin`, stdout` and  stderr`, if set.
/// Standard IO channel can be redirected to one of the following:
///
/// - a temporary pipe created via `read_from_process` or `write_to_process`,
///   which can be used to read from/write to the process directly
/// - a file on the filesystem, via `redirect_to_file` or `redirect_from_file`
/// - an existing `@pipe.PipeRead` or `@pipe.PipeWrite`,
///   for example redirecting standard error to standard out.
///
/// Note than when passing an existing pipe to the process,
/// the ownership of the pipe is *NOT* transferred.
/// So the caller should still close the channel manually when apporiate.
///
/// If `cwd` is present, the spawned command will be executed
/// in the directory specified by `cwd`.
pub async fn run(
  cmd : String,
  args : Array[String],
  extra_env? : Map[String, String] = {},
  inherit_env? : Bool = true,
  stdin? : &ProcessInput,
  stdout? : &ProcessOutput,
  stderr? : &ProcessOutput,
  cwd? : String,
) -> Int {
  let context = "@process.run()"
  let pid = spawn(
    cmd,
    args,
    extra_env~,
    inherit_env~,
    stdin~,
    stdout~,
    stderr~,
    cwd~,
    context~,
  )
  @event_loop.wait_pid(pid) catch {
    err if @coroutine.is_being_cancelled() => {
      terminate_process(pid)
      raise err
    }
    err => raise err
  }
  let out = @ref.new(0)
  let ret = get_process_result(pid, out)
  if ret < 0 {
    @os_error.check_errno(context)
  }
  out.val
}

///|
/// Run a process and collect its standard output.
/// Return the exit code of the process and the content of its standard output.
///
/// The meaning of parameters is the same as `@process.run`
pub async fn collect_stdout(
  cmd : String,
  args : Array[String],
  extra_env? : Map[String, String] = {},
  inherit_env? : Bool = true,
  stdin? : &ProcessInput,
  stderr? : &ProcessOutput,
  cwd? : String,
) -> (Int, &@io.Data) {
  let (r, w) = read_from_process()
  @async.with_task_group(fn(group) {
    defer r.close()
    let exit_code = group.spawn(() => run(
      cmd,
      args,
      extra_env~,
      inherit_env~,
      stdin?,
      stdout=w,
      stderr?,
      cwd?,
    ))
    let output = r.read_all()
    (exit_code.wait(), output)
  })
}

///|
/// Run a process and collect its standard error.
/// Return the exit code of the process and the content of its standard error.
///
/// The meaning of parameters is the same as `@process.run`
pub async fn collect_stderr(
  cmd : String,
  args : Array[String],
  extra_env? : Map[String, String] = {},
  inherit_env? : Bool = true,
  stdin? : &ProcessInput,
  stdout? : &ProcessOutput,
  cwd? : String,
) -> (Int, &@io.Data) {
  let (r, w) = read_from_process()
  @async.with_task_group(fn(group) {
    defer r.close()
    let exit_code = group.spawn(() => run(
      cmd,
      args,
      extra_env~,
      inherit_env~,
      stdin?,
      stdout?,
      stderr=w,
      cwd?,
    ))
    let output = r.read_all()
    (exit_code.wait(), output)
  })
}

///|
/// Run a process and collect its standard output & standard error.
/// Return the exit code of the process, the content of its standard output,
/// and the content of its standard error.
///
/// The meaning of parameters is the same as `@process.run`
pub async fn collect_output(
  cmd : String,
  args : Array[String],
  extra_env? : Map[String, String] = {},
  inherit_env? : Bool = true,
  stdin? : &ProcessInput,
  cwd? : String,
) -> (Int, &@io.Data, &@io.Data) {
  let (r_out, w_out) = read_from_process()
  let (r_err, w_err) = read_from_process()
  @async.with_task_group(fn(group) {
    defer r_out.close()
    defer r_err.close()
    let exit_code = group.spawn(() => run(
      cmd,
      args,
      extra_env~,
      inherit_env~,
      stdin?,
      stdout=w_out,
      stderr=w_err,
      cwd?,
    ))
    let stdout = r_out.read_all()
    let stderr = r_err.read_all()
    (exit_code.wait(), stdout, stderr)
  })
}

///|
/// Run a process, merge and collect its standard output & standard error.
/// Return the exit code of the process,
/// and the content of its standard output and standard error.
///
/// The meaning of parameters is the same as `@process.run`
pub async fn collect_output_merged(
  cmd : String,
  args : Array[String],
  extra_env? : Map[String, String] = {},
  inherit_env? : Bool = true,
  stdin? : &ProcessInput,
  cwd? : String,
) -> (Int, &@io.Data) {
  let (r, w) = read_from_process()
  @async.with_task_group(fn(group) {
    defer r.close()
    let exit_code = group.spawn(() => run(
      cmd,
      args,
      extra_env~,
      inherit_env~,
      stdin?,
      stdout=w,
      stderr=w,
      cwd?,
    ))
    let output = r.read_all()
    (exit_code.wait(), output)
  })
}

///|
/// Create a temporary pipe for reading from stdout/stderr of a process.
/// The return value is a pair `(r, w)`,
/// where `r` is a `@pipe.PipeRead` that can be used to read process output,
/// and `w` should be passed to `@process.run`.
///
/// `w` is temporary: it can only be passed to one `@process.run` call.
/// However, it is safe to pass `w` to both `stdout` and `stderr` of the same process.
pub fn read_from_process() -> (@pipe.PipeRead, &ProcessOutput) raise {
  let (r, w) = @pipe.pipe()
  (r, TempPipeWrite::{ pipe: w, closed: false })
}

///|
/// Create a temporary pipe for writing to stdin of a process.
/// The return value is a pair `(r, w)`,
/// where `w` is a `@pipe.PipeWrite` that can be used to write to process output,
/// and `r` should be passed to `@process.run`.
pub fn write_to_process() -> (&ProcessInput, @pipe.PipeWrite) raise {
  let (r, w) = @pipe.pipe()
  (TempPipeRead::{ pipe: r, closed: false }, w)
}

///|
/// Redirect the output of a process to the file at `path`.
/// The meaning of `append`, `create` and `truncate` is the same as `@fs.open`,
/// see the document of `@fs.open` for more details.
pub async fn redirect_to_file(
  path : String,
  append? : Bool = false,
  create? : Int,
  truncate? : Bool = false,
) -> &ProcessOutput {
  RedirectToFile(@fs.open(path, mode=WriteOnly, create?, append~, truncate~))
}

///|
/// Redirect the content of a file at `path` to the stdin of a process.
pub async fn redirect_from_file(path : String) -> &ProcessInput {
  RedirectToFile(@fs.open(path, mode=ReadOnly))
}

///|
/// An entity that can be used to redirect stdin of a process
trait ProcessInput {
  fd(Self) -> Int
  after_spawn(Self) -> Unit = _
}

///|
/// Default implementation for after_spawn cleanup. Does nothing.
impl ProcessInput with after_spawn(_) {
  ()
}

///|
/// Implementation of ProcessInput trait for @pipe.PipeRead.
/// Allows pipe readers to be used as process input (stdin).
pub impl ProcessInput for @pipe.PipeRead with fd(self) {
  self.fd()
}

///|
/// An entity that can be used to redirect stdout/stderr of a process
trait ProcessOutput {
  fd(Self) -> Int
  after_spawn(Self) -> Unit = _
}

///|
/// Default implementation for after_spawn cleanup. Does nothing.
impl ProcessOutput with after_spawn(_) {
  ()
}

///|
/// Implementation of ProcessOutput trait for @pipe.PipeWrite.
/// Allows pipe writers to be used as process output (stdout/stderr).
pub impl ProcessOutput for @pipe.PipeWrite with fd(self) {
  self.fd()
}

///|
/// Internal wrapper for pipe reads used in temporary process pipes.
/// The `closed` flag ensures proper cleanup when the process starts.
priv struct TempPipeRead {
  pipe : @pipe.PipeRead
  mut closed : Bool
}

///|
/// Internal wrapper for pipe writes used in temporary process pipes.
/// The `closed` flag ensures proper cleanup when the process starts.
priv struct TempPipeWrite {
  pipe : @pipe.PipeWrite
  mut closed : Bool
}

///|
/// Returns the file descriptor of the wrapped pipe.
impl ProcessOutput for TempPipeWrite with fd(self) {
  self.pipe.fd()
}

///|
/// Cleans up the pipe after process spawning by closing it.
impl ProcessOutput for TempPipeWrite with after_spawn(self) {
  if !self.closed {
    self.closed = true
    self.pipe.close()
  }
}

///|
/// Returns the file descriptor of the wrapped pipe.
impl ProcessInput for TempPipeRead with fd(self) {
  self.pipe.fd()
}

///|
/// Cleans up the pipe after process spawning by closing it.
impl ProcessInput for TempPipeRead with after_spawn(self) {
  if !self.closed {
    self.closed = true
    self.pipe.close()
  }
}

///|
/// Internal wrapper for file-based I/O redirection.
/// Wraps a file handle for use as process input or output.
priv struct RedirectToFile(@fs.File)

///|
/// Returns the file descriptor of the wrapped file.
impl ProcessOutput for RedirectToFile with fd(self) {
  self.0.fd()
}

///|
/// Closes the file after process spawning.
impl ProcessOutput for RedirectToFile with after_spawn(self) {
  self.0.close()
}

///|
/// Returns the file descriptor of the wrapped file.
impl ProcessInput for RedirectToFile with fd(self) {
  self.0.fd()
}

///|
/// Closes the file after process spawning.
impl ProcessInput for RedirectToFile with after_spawn(self) {
  self.0.close()
}
