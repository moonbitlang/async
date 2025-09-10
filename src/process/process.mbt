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
extern "C" fn get_curr_env() -> FixedArray[Bytes?] = "moonbitlang_async_get_curr_env"

///|
let curr_env : FixedArray[Bytes?] = get_curr_env()

///|
extern "C" fn terminate_process(pid : Int) = "moonbitlang_async_terminate_process"

///|
/// Execute a system process with command `cmd`,
/// and provide `args` as extra arguments to `cmd.
/// Both `cmd` and elements of `args` must not contain `'\0'`.
///
/// `run` will block until the new process terminates,
/// and returns the exit status of the process.
/// If current task is cancelled while blocking,
/// the spawned process will be terminated via `SIGTERM`,
/// unless `orphan` is `true` (`false` by default).
/// To run the process in background, use `@async.spawn` or `@async.spawn_bg`.
///
/// If `inherit_env` is `true` (`true` by default),
/// the new process will inherit environment variables of current process.
///
/// `extra_env`, if present, will set extra environment variables for the new process
/// (in addition to those inherited ones, if `inherit_env` is `true`).
/// Keys and values of `extra_env` must not contain `'\0'`.
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
  cmd : Bytes,
  args : Array[Bytes],
  extra_env? : Map[Bytes, Bytes] = {},
  inherit_env? : Bool = true,
  stdin? : &ProcessInput,
  stdout? : &ProcessOutput,
  stderr? : &ProcessOutput,
  cwd? : Bytes,
  orphan? : Bool = false,
) -> Int raise {
  let argv = FixedArray::make(args.length() + 2, None)
  argv[0] = Some(cmd)
  for i in 0..<args.length() {
    argv[i + 1] = Some(args[i])
  }
  let pid = {
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
          @fd_util.set_blocking(pipe.fd())
          pipe.fd()
        }
        None => -1
      }
      let stdout = match stdout {
        Some(pipe) => {
          @fd_util.set_blocking(pipe.fd())
          pipe.fd()
        }
        None => -1
      }
      let stderr = match stderr {
        Some(pipe) => {
          @fd_util.set_blocking(pipe.fd())
          pipe.fd()
        }
        None => -1
      }
      let extra_count = extra_env.size()
      let env = match (inherit_env, extra_count) {
        (true, 0) => curr_env
        (false, 0) => [None]
        (_, n) => {
          let curr_env = if inherit_env { curr_env } else { [None] }
          let envp = FixedArray::make(n + curr_env.length(), None)
          let mut i = 0
          for k, v in extra_env {
            envp[i] = Some(k + b"=" + v)
            i = i + 1
          }
          curr_env.blit_to(
            envp,
            src_offset=0,
            dst_offset=i,
            len=curr_env.length(),
          )
          envp
        }
      }
      let job = @event_loop.Spawn(
        path=cmd,
        args=argv,
        env~,
        stdin~,
        stdout~,
        stderr~,
        cwd~,
      )
      @event_loop.perform_job(job)
    }
  @event_loop.perform_job(WaitProcess(pid)) catch {
    err if !orphan && @coroutine.is_being_cancelled() => {
      terminate_process(pid)
      raise err
    }
    err => raise err
  }
}

///|
/// Create a temporary pipe for reading from stdout/stderr of a process.
pub fn read_from_process() -> (@pipe.PipeRead, &ProcessOutput) raise {
  let (r, w) = @pipe.pipe()
  (r, TempPipeWrite(w))
}

///|
/// Create a temporary pipe for writing to stdin of a process.
pub fn write_to_process() -> (&ProcessInput, @pipe.PipeWrite) raise {
  let (r, w) = @pipe.pipe()
  (TempPipeRead(r), w)
}

///|
/// Redirect the output of a process to the file at `path`.
/// The meaning of `append`, `create` and `truncate` is the same as `@fs.open`,
/// see the document of `@fs.open` for more details.
pub async fn redirect_to_file(
  path : Bytes,
  append? : Bool = false,
  create? : Int,
  truncate? : Bool = false,
) -> &ProcessOutput raise {
  RedirectToFile(@fs.open(path, mode=WriteOnly, create?, append~, truncate~))
}

///|
/// Redirect the content of a file at `path` to the stdin of a process.
pub async fn redirect_from_file(path : Bytes) -> &ProcessInput raise {
  RedirectToFile(@fs.open(path, mode=ReadOnly))
}

///|
/// An entity that can be used to redirect stdin of a process
trait ProcessInput {
  fd(Self) -> Int
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
/// An entity that can be used to redirect stdout/stderr of a process
trait ProcessOutput {
  fd(Self) -> Int
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
priv struct TempPipeRead(@pipe.PipeRead)

///|
priv struct TempPipeWrite(@pipe.PipeWrite)

///|
impl ProcessOutput for TempPipeWrite with fd(self) {
  self.0.fd()
}

///|
impl ProcessOutput for TempPipeWrite with after_spawn(self) {
  self.0.close()
}

///|
impl ProcessInput for TempPipeRead with fd(self) {
  self.0.fd()
}

///|
impl ProcessInput for TempPipeRead with after_spawn(self) {
  self.0.close()
}

///|
priv struct RedirectToFile(@fs.File)

///|
impl ProcessOutput for RedirectToFile with fd(self) {
  self.0.fd()
}

///|
impl ProcessOutput for RedirectToFile with after_spawn(self) {
  self.0.close()
}

///|
impl ProcessInput for RedirectToFile with fd(self) {
  self.0.fd()
}

///|
impl ProcessInput for RedirectToFile with after_spawn(self) {
  self.0.close()
}
