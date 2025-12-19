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
#cfg(not(platform="windows"))
extern "C" fn get_curr_env() -> FixedArray[@os_string.OsString?] = "moonbitlang_async_get_curr_env"

///|
#cfg(not(platform="windows"))
let curr_env : FixedArray[@os_string.OsString?] = get_curr_env()

///|
#cfg(platform="windows")
extern "C" fn get_curr_env() -> String = "moonbitlang_async_get_curr_env"

///|
#cfg(platform="windows")
let curr_env : String = get_curr_env()

///|
extern "C" fn terminate_process(pid : Int) = "moonbitlang_async_terminate_process"

///|
#borrow(out)
extern "C" fn get_process_result(pid : Int, out : Ref[Int]) -> Int = "moonbitlang_async_get_process_result"

///|
#cfg(not(platform="windows"))
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
  let cmd = @os_string.encode(cmd)
  let argv = FixedArray::make(args.length() + 2, None)
  let cwd = match cwd {
    None => None
    Some(cwd) => Some(@os_string.encode(cwd))
  }
  argv[0] = Some(cmd)
  for i in 0..<args.length() {
    argv[i + 1] = Some(@os_string.encode(args[i]))
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
        envp[i] = Some(@os_string.encode("\{k}=\{v}"))
        i = i + 1
      }
      curr_env.blit_to(envp, src_offset=0, dst_offset=i, len=curr_env.length())
      envp
    }
  }
  @event_loop.spawn(cmd, argv, env~, stdin~, stdout~, stderr~, cwd~, context~)
}

///|
#cfg(platform="windows")
fn StringBuilder::write_arg_with_windows_escape(
  builder : StringBuilder,
  arg : String,
) -> Unit raise {
  let mut segment_start = 0
  let mut index = 0
  let mut trailing_backslash = 0
  fn flush(skip : Int) raise {
    if index > segment_start {
      builder.write_stringview(arg[segment_start:index - trailing_backslash])
      if trailing_backslash > 0 {
        builder.write_string(String::make(trailing_backslash * 2, '\\'))
      }
      segment_start = index + skip
    }
  }

  builder.write_char('"')
  while index < arg.length() {
    match arg.code_unit_at(index) {
      '"' => {
        flush(1)
        builder.write_string("\\\"")
      }
      '\\' => trailing_backslash += 1
      _ => trailing_backslash = 0
    }
    index += 1
  }
  flush(0)
  builder.write_char('"')
}

///|
#cfg(platform="windows")
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
  let cmd = match cmd {
    [.., .. ".exe"] => cmd
    _ => cmd + ".exe"
  }
  let command_line = StringBuilder::new()
  command_line.write_arg_with_windows_escape(cmd)
  for arg in args {
    command_line..write_char(' ')..write_arg_with_windows_escape(arg)
  }
  let command_line = @os_string.encode(command_line.to_string())
  let cwd = match cwd {
    None => None
    Some(cwd) => Some(@os_string.encode(cwd))
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
    Some(pipe) => pipe.fd()
    None => @fd_util.invalid_fd
  }
  let stdout = match stdout {
    Some(pipe) => pipe.fd()
    None => @fd_util.invalid_fd
  }
  let stderr = match stderr {
    Some(pipe) => pipe.fd()
    None => @fd_util.invalid_fd
  }
  let env = match (inherit_env, extra_env.is_empty()) {
    (true, true) => None
    (false, true) => Some(@os_string.encode("\u{0}"))
    (_, false) => {
      let env = StringBuilder::new()
      for key, value in extra_env {
        env
        ..write_string(key)
        ..write_char('=')
        ..write_string(value)
        ..write_string("\u{0}")
      }
      if inherit_env {
        env.write_string(curr_env)
      } else {
        env.write_string("\u{0}")
      }
      Some(@os_string.encode(env.to_string()))
    }
  }
  @event_loop.spawn(
    command_line,
    env~,
    stdin~,
    stdout~,
    stderr~,
    cwd~,
    context~,
  )
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
  @event_loop.wait_pid(pid, context~)
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
  @event_loop.wait_pid(pid, context~) catch {
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
    let stdout = group.spawn(() => {
      defer r_out.close()
      r_out.read_all()
    })
    let stderr = group.spawn(() => {
      defer r_err.close()
      r_err.read_all()
    })
    (exit_code.wait(), stdout.wait(), stderr.wait())
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
  let (create, mode) = match create {
    Some(mode) => (true, mode)
    None => (false, 0)
  }
  let (fd, kind) = @event_loop.open_detached(
    path,
    1, // write only
    create~,
    append~,
    truncate~,
    sync=0,
    mode~,
    is_async=false,
    context="@process.redirect_to_file()",
  )
  RedirectToFile(fd, kind)
}

///|
/// Redirect the content of a file at `path` to the stdin of a process.
pub async fn redirect_from_file(path : String) -> &ProcessInput {
  let (fd, kind) = @event_loop.open_detached(
    path,
    0, // read only
    create=false,
    append=false,
    truncate=false,
    sync=0,
    mode=0,
    is_async=false,
    context="@process.redirect_to_file()",
  )
  RedirectToFile(fd, kind)
}

///|
/// An entity that can be used to redirect stdin of a process
trait ProcessInput {
  fd(Self) -> @fd_util.Fd
  after_spawn(Self) -> Unit = _
}

///|
impl ProcessInput with after_spawn(_) {
  ()
}

///|
pub impl ProcessInput for @pipe.PipeRead with fd(self) {
  self.fd()
}

///|
pub impl ProcessInput for @stdio.Input with fd(self) {
  self.fd()
}

///|
/// An entity that can be used to redirect stdout/stderr of a process
trait ProcessOutput {
  fd(Self) -> @fd_util.Fd
  after_spawn(Self) -> Unit = _
}

///|
impl ProcessOutput with after_spawn(_) {
  ()
}

///|
pub impl ProcessOutput for @pipe.PipeWrite with fd(self) {
  self.fd()
}

///|
pub impl ProcessOutput for @stdio.Output with fd(self) {
  self.fd()
}

///|
priv struct TempPipeRead {
  pipe : @pipe.PipeRead
  mut closed : Bool
}

///|
priv struct TempPipeWrite {
  pipe : @pipe.PipeWrite
  mut closed : Bool
}

///|
impl ProcessOutput for TempPipeWrite with fd(self) {
  self.pipe.fd()
}

///|
impl ProcessOutput for TempPipeWrite with after_spawn(self) {
  if !self.closed {
    self.closed = true
    self.pipe.close()
  }
}

///|
impl ProcessInput for TempPipeRead with fd(self) {
  self.pipe.fd()
}

///|
impl ProcessInput for TempPipeRead with after_spawn(self) {
  if !self.closed {
    self.closed = true
    self.pipe.close()
  }
}

///|
priv struct RedirectToFile(@fd_util.Fd, @fd_util.FileKind)

///|
impl ProcessOutput for RedirectToFile with fd(self) {
  self.0
}

///|
impl ProcessOutput for RedirectToFile with after_spawn(self) {
  @fd_util.close(self.0, kind=self.1, context="") catch {
    _ => ()
  }
}

///|
impl ProcessInput for RedirectToFile with fd(self) {
  self.0
}

///|
impl ProcessInput for RedirectToFile with after_spawn(self) {
  @fd_util.close(self.0, kind=self.1, context="") catch {
    _ => ()
  }
}
