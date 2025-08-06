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
/// `stdin`, `stdout` and `stderr`, if set,
/// the corresponding channel of the new process will be redirected to the given pipe.
/// The ownership of `stdin`, `stdout`, and `stderr` will be transferred to the `spawn`,
/// current process MUST NOT read/write/close these pipes any more, even if `spawn` fails.
pub async fn run(
  cmd : Bytes,
  args : Array[Bytes],
  extra_env~ : Map[Bytes, Bytes] = {},
  inherit_env~ : Bool = true,
  stdin? : @pipe.PipeRead,
  stdout? : @pipe.PipeWrite,
  stderr? : @pipe.PipeWrite,
  orphan~ : Bool = false,
) -> Int raise {
  let argv = FixedArray::make(args.length() + 2, None)
  argv[0] = Some(cmd)
  for i in 0..<args.length() {
    argv[i + 1] = Some(args[i])
  }
  fn close(fd) {
    @fd_util.close(fd) catch {
      _ => ()
    }
  }

  defer {
    if stdin is Some(pipe) {
      close(pipe.fd())
    }
    if stdout is Some(pipe) {
      close(pipe.fd())
    }
    if stderr is Some(pipe) {
      close(pipe.fd())
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
      curr_env.blit_to(envp, src_offset=0, dst_offset=i, len=curr_env.length())
      envp
    }
  }
  let job = @thread_pool.spawn_job(cmd, argv, env, stdin, stdout, stderr)
  let pid = @event_loop.perform_job(job)
  @event_loop.wait_pid(pid) catch {
    err if !orphan && @coroutine.is_being_cancelled() => {
      terminate_process(pid)
      raise err
    }
    err => raise err
  }
}
