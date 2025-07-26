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
struct Process {
  pid : Int
  mut exit_status : Int?
}

///|
extern "C" fn get_curr_env() -> FixedArray[Bytes?] = "moonbitlang_async_get_curr_env"

///|
let curr_env : FixedArray[Bytes?] = get_curr_env()

///|
pub async fn spawn(
  cmd : Bytes,
  args : Array[Bytes],
  extra_env~ : Map[Bytes, Bytes] = {},
  inherit_env~ : Bool = true,
  stdin? : @pipe.PipeRead,
  stdout? : @pipe.PipeWrite,
  stderr? : @pipe.PipeWrite,
) -> Process raise {
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
        envp[i] = Some(k + b"=" + v + "\x00")
        i = i + 1
      }
      curr_env.blit_to(envp, src_offset=0, dst_offset=i, len=curr_env.length())
      envp
    }
  }
  let job = @thread_pool.spawn_job(cmd, argv, env, stdin, stdout, stderr)
  { pid: @event_loop.perform_job(job), exit_status: None }
}

///|
pub async fn Process::wait(self : Process) -> Int raise {
  if self.exit_status is Some(status) {
    return status
  }
  let status = @event_loop.wait_pid(self.pid)
  self.exit_status = Some(status)
  status
}
