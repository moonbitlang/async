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
/// Execute a system process with command `cmd`,
/// and provide `args` as extra arguments to `cmd.
/// Both `cmd` and elements of `args` are encoded using UTF8.
/// The process ID of the spawned process will be returned.
///
/// The spawned process would be *orphan*, meaning that it will
/// keep running until completion or explicitly terminated,
/// even if the task that calls `spawn_orphan` is cancelled.
/// Users are recommended to use `@process.run` whenever possible,
/// because `@process.spawn`/`@process.run` has better structured concurrency integration.
/// `spawn_orphan` should only be used when the process is intended to be orphan
/// (i.e. keep running after parent process terminates).
///
/// The meaning of the arguments is the same as `@process.spawn`,
/// see `@process.spawn` for more details.
pub async fn spawn_orphan(
  cmd : StringView,
  args : ArrayView[String],
  extra_env? : Map[String, String] = Map([]),
  inherit_env? : Bool = true,
  stdin? : &ProcessInput = @stdio.stdin,
  stdout? : &ProcessOutput = @stdio.stdout,
  stderr? : &ProcessOutput = @stdio.stderr,
  cwd? : StringView,
  no_console_window? : Bool = false,
) -> Int {
  let (proc, stdin, stdout, stderr) = raw_spawn(
    cmd,
    args,
    extra_env~,
    inherit_env~,
    stdin~,
    stdout~,
    stderr~,
    cwd~,
    no_console_window~,
    is_orphan=true,
    context="@process.spawn_orphan()",
  )
  defer proc.close()
  stdin.close()
  stdout.close()
  stderr.close()
  proc.pid
}

///|
/// Wait for the process with specfic ID to terminate,
/// and return the exit code of the process.
/// If the process is killed by a signal, the result would be `-signal_number`.
pub async fn wait_pid(pid : Int) -> Int {
  let context = "@process.wait_pid()"
  let process = @event_loop.Process::from_pid(pid, context~)
  defer process.close()
  process.wait_pid(context~)
}

///|
/// Execute a system process with command `cmd`,
/// and provide `args` as extra arguments to `cmd.
///
/// All arguments of `@process.run` has the same meaning as `@process.spawn`,
/// see `@process.spawn` for more details.
///
/// Instead of spawning the child process in a task group,
/// run will simply block and wait for completion of the child process in current task.
/// If `@process.run()` is cancelled after the child process started,
/// the child process will be cancelled automatically as well, and `@process.run()` will return
/// only after the child completes its cleanup and actually terminates.
///
/// `@process.run()` does not expose a `Process` object for the child,
/// so the caller cannot retrieve the PID of the child process,
/// or access `.stdin`/`.stdout`/`.stderr` of the child process.
/// As a consequence, `@process.read_from_process()`/`@process.write_to_process()`
/// cannot be used with `@process.run()`.
/// When current process need to interact with the child,
/// use `@process.collect_*` helpers or `@process.spawn` instead.
pub async fn run(
  cmd : StringView,
  args : ArrayView[String],
  extra_env? : Map[String, String] = Map([]),
  inherit_env? : Bool = true,
  stdin? : &ProcessInput = @stdio.stdin,
  stdout? : &ProcessOutput = @stdio.stdout,
  stderr? : &ProcessOutput = @stdio.stderr,
  cwd? : StringView,
  no_console_window? : Bool = false,
  cancel_handler? : CancellationHandler = graceful_cancel(timeout=5000),
) -> Int {
  let context = "@process.run()"
  let (process, stdin, stdout, stderr) = raw_spawn(
    cmd,
    args,
    extra_env~,
    inherit_env~,
    stdin~,
    stdout~,
    stderr~,
    cwd~,
    no_console_window~,
    is_orphan=false,
    context~,
  )
  defer process.close()
  // The caller of `run` has no way to obtain these parent side channels,
  // so close them immediately to avoid leak & hang up.
  // Caller of `run` should not use `read_from_process`/`write_to_process` in general.
  stdin.close()
  stdout.close()
  stderr.close()
  let pid = process.pid
  match @async.handle_cancellation(() => process.wait_pid(context~)) {
    None => {
      @async.protect_from_cancel() <| () => {
        @async.with_task_group() <| group => {
          group.spawn_bg(no_wait=true, () => cancel_handler(pid))
          ignore <| process.wait_pid(context~)
        }
      }
      @coroutine.raise_cancellation_signal()
    }
    Some(ret) => ret
  }
}

///|
/// A handle to a spawned process
pub struct Process {
  pid : Int
  /// Redirected `stdin` channel of the process.
  /// This field is only meaningful if the process is spawned
  /// with `stdin` redirected to `@process.write_to_process()`.
  /// In this case, it can be used to write to stdin of the child process.
  stdin : WriteToProcess
  /// Redirected `stdout` channel of the process.
  /// This field is only meaningful if the process is spawned
  /// with `stdout` redirected to `@process.read_from_process()`.
  /// In this case, it can be used to read from the stdout of the child process.
  stdout : ReadFromProcess
  /// Redirected `stderr` channel of the process.
  /// This field is only meaningful if the process is spawned
  /// with `stderr` redirected to `@process.read_from_process()`.
  /// In this case, it can be used to read from the stderr of the child process.
  stderr : ReadFromProcess
  priv result : @async.Task[Int]
}

///|
/// Wait for a process to terminate, return the exit code of the process
/// If the process is killed by a signal, the result would be `-signal_number`.
pub async fn Process::wait(self : Process) -> Int {
  self.result.wait()
}

///|
/// If the process already terminated, return its exit code.
/// If the process is killed by a signal, the result would be `-signal_number`.
/// If the process is still running, return `None`.
pub fn Process::try_wait(self : Process) -> Int? raise {
  self.result.try_wait()
}

///|
/// Cancel a child process.
/// The method of cancellation is determined by the `cancel_handler` parameter of `@process.spawn`.
/// Notice that after `.cancel()` is called,
/// if may take a while before the child process actually terminates.
/// Use `.wait()` to wait for actual termination of the child process.
pub fn Process::cancel(self : Process) -> Unit {
  self.result.cancel()
}

///|
/// Spawn a child process inside a task group.
/// The child process runs the program on path `cmd`,
/// and `args` will be provided to the program as command line arguments.
/// On Linux/MacOS, both `cmd` and `args` are encoded using UTF-8.
/// On Windows, both `cmd` and `args` are passed via native unicode string,
/// and `args` will be converted to Windows-style command line string via C argv splitting rule.
///
/// If `no_wait` is `false` (`fales` by default),
/// the task group will wait for termination of the child process before returning normally.
/// When the task group is about to exit, for example due to fatal error, external cancellation,
/// the child process will be terminated automatically.
///
/// A `Process` object will be returned,
/// users can retrieve the PID of the spawned process via `.pid`
/// or wait for the process to terminate via `.wait()`/`.try_wait()`.
///
/// The standard IO of the new process will be redirected to the value of `stdin`, stdout` and `stderr`.
/// By default the child process will inherit corresponding stdio channels from current process.
/// Standard IO channel can be redirected to one of the following:
///
/// - `@process.read_from_process()`, `@process.write_to_process()`,
///   `@process.read_from_process_shared()` and `@process.write_to_process_shared()`
///   can be used to interact with the child from current process
/// - `@process.pipe()` can be used to connect input/output channels of multiple children process
/// - `@process.redirect_to_file()`, `@process.rerdirect_from_file()`,
///   `@process.redirect_to_file_shared()` and `@process.rerdirect_from_file_shared()`
///   can be used to redirect input/output to a file path
/// - `@stdio.stdin`, `@stdio.stdout` and `@stdio.stderr` can also be used for redirection directly
/// - `@process.duplicate_stdout()` can be used to redirect stderr,
///   in this case the child process's stderr channel will be the same as its stdout channel
///
/// See the document of the above functions for more detail on each kind of redirection,
/// in particular resource management contract on various objects involved.
///
/// If `inherit_env` is `true` (`true` by default),
/// the new process will inherit environment variables of current process.
///
/// `extra_env`, if present, will set extra environment variables for the new process
/// (in addition to and overriding those inherited ones, if `inherit_env` is `true`).
/// Keys and values of `extra_env` are encoded using UTF8.
///
/// If `cwd` is present, the spawned command will be executed
/// in the directory specified by `cwd`.
///
/// When `no_console_window` is `true` (`false` by default),
/// creation of a new console window will be disabled on Windows.
/// By default a new console window may be created
/// when the calling process is a GUI application
/// and the child process is a conlose application.
/// `no_console_window` has no effect on non-Windows platforms.
///
/// The child process can be cancelled manually via `.cancel()` on the returned `Process` object.
/// The child may also get cancelled automatically by the task group.
/// When the child process is cancelled, `cancel_handler` will be used to automatically stop the process.
/// The default value of `cancel_handler` is `graceful_cancel(timeout=5000)`
/// (First try to gracefully terminate the process,
/// and if the process is still running after five seconds, terminate it forcefully).
/// Note that the task group will not exit until the child process actually terminates
/// (i.e. after the child process completes its cleanup process).
/// So the child process will never leak outside its task group.
///
/// If `cancel_handler` is still running after the process terminates,
/// it will be cancelled.
pub async fn spawn(
  group : @async.TaskGroup,
  cmd : StringView,
  args : ArrayView[String],
  extra_env? : Map[String, String] = Map([]),
  inherit_env? : Bool = true,
  stdin? : &ProcessInput = @stdio.stdin,
  stdout? : &ProcessOutput = @stdio.stdout,
  stderr? : &ProcessOutput = @stdio.stderr,
  cwd? : StringView,
  no_console_window? : Bool = false,
  cancel_handler? : CancellationHandler = graceful_cancel(timeout=5000),
  no_wait? : Bool,
) -> Process {
  let context = "@process.spawn()"
  let (process, stdin, stdout, stderr) = raw_spawn(
    cmd,
    args,
    extra_env~,
    inherit_env~,
    stdin~,
    stdout~,
    stderr~,
    cwd~,
    no_console_window~,
    is_orphan=false,
    context~,
  )
  let pid = process.pid
  let result = group.spawn(no_wait?, () => {
    defer process.close()
    match @async.handle_cancellation(() => process.wait_pid(context~)) {
      None => {
        let mut result = 0
        @async.protect_from_cancel() <| () => {
          @async.with_task_group() <| group => {
            group.spawn_bg(no_wait=true, () => cancel_handler(pid))
            result = process.wait_pid(context~)
          }
        }
        result
      }
      Some(ret) => ret
    }
  })
  { pid, stdin, stdout, stderr, result, }
}

///|
/// Run a process and collect its standard output.
/// Return the exit code of the process and the content of its standard output.
///
/// The meaning of parameters is the same as `@process.run`
pub async fn collect_stdout(
  cmd : StringView,
  args : ArrayView[String],
  extra_env? : Map[String, String] = Map([]),
  inherit_env? : Bool = true,
  stdin? : &ProcessInput,
  stderr? : &ProcessOutput,
  cwd? : StringView,
  no_console_window? : Bool,
) -> (Int, &@io.Data) {
  let mut result = None
  @async.with_task_group() <| group => {
    let child = spawn(
      group,
      cmd,
      args,
      extra_env~,
      inherit_env~,
      stdin?,
      stdout=read_from_process(),
      stderr?,
      cwd?,
      no_console_window?,
    )
    defer child.stdout.close()
    // The caller cannot obtain these channels
    child.stdin.close()
    child.stderr.close()
    let output = child.stdout.read_all()
    result = Some((child.wait(), output))
  }
  result.unwrap()
}

///|
/// Run a process and collect its standard error.
/// Return the exit code of the process and the content of its standard error.
///
/// The meaning of parameters is the same as `@process.run`
pub async fn collect_stderr(
  cmd : StringView,
  args : ArrayView[String],
  extra_env? : Map[String, String] = Map([]),
  inherit_env? : Bool = true,
  stdin? : &ProcessInput,
  stdout? : &ProcessOutput,
  cwd? : StringView,
  no_console_window? : Bool,
) -> (Int, &@io.Data) {
  let mut result = None
  @async.with_task_group() <| group => {
    let child = spawn(
      group,
      cmd,
      args,
      extra_env~,
      inherit_env~,
      stdin?,
      stdout?,
      stderr=read_from_process(),
      cwd?,
      no_console_window?,
    )
    defer child.stderr.close()
    // The caller cannot obtain these channels
    child.stdin.close()
    child.stdout.close()
    let output = child.stderr.read_all()
    result = Some((child.wait(), output))
  }
  result.unwrap()
}

///|
/// Run a process and collect its standard output & standard error.
/// Return the exit code of the process, the content of its standard output,
/// and the content of its standard error.
///
/// The meaning of parameters is the same as `@process.run`
pub async fn collect_output(
  cmd : StringView,
  args : ArrayView[String],
  extra_env? : Map[String, String] = Map([]),
  inherit_env? : Bool = true,
  stdin? : &ProcessInput,
  cwd? : StringView,
  no_console_window? : Bool,
) -> (Int, &@io.Data, &@io.Data) {
  let mut result = None
  @async.with_task_group() <| group => {
    let child = spawn(
      group,
      cmd,
      args,
      extra_env~,
      inherit_env~,
      stdin?,
      stdout=read_from_process(),
      stderr=read_from_process(),
      cwd?,
      no_console_window?,
    )
    // The caller cannot obtain this channel
    child.stdin.close()
    let stdout = group.spawn(() => {
      defer child.stdout.close()
      child.stdout.read_all()
    })
    let stderr = group.spawn(() => {
      defer child.stderr.close()
      child.stderr.read_all()
    })
    result = Some((child.wait(), stdout.wait(), stderr.wait()))
  }
  result.unwrap()
}

///|
/// Run a process, merge and collect its standard output & standard error.
/// Return the exit code of the process,
/// and the content of its standard output and standard error.
///
/// The meaning of parameters is the same as `@process.run`
pub async fn collect_output_merged(
  cmd : StringView,
  args : Array[String],
  extra_env? : Map[String, String] = Map([]),
  inherit_env? : Bool = true,
  stdin? : &ProcessInput,
  cwd? : StringView,
  no_console_window? : Bool,
) -> (Int, &@io.Data) {
  let mut result = None
  @async.with_task_group() <| group => {
    let child = spawn(
      group,
      cmd,
      args,
      extra_env~,
      inherit_env~,
      stdin?,
      stdout=read_from_process(),
      stderr=duplicate_stdout(),
      cwd?,
      no_console_window?,
    )
    defer child.stdout.close()
    // The caller cannot obtain this channel
    child.stdin.close()
    let output = child.stdout.read_all()
    result = Some((child.wait(), output))
  }
  result.unwrap()
}
