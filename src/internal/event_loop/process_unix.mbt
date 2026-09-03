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
pub async fn spawn_unix(
  path : @os_string.OsString,
  args : SpawnJobArgv,
  env~ : SpawnJobEnv,
  stdin~ : @fd_util.Fd,
  stdout~ : @fd_util.Fd,
  stderr~ : @fd_util.Fd,
  is_orphan~ : Bool,
  cwd~ : @os_string.OsString?,
  context~ : String,
) -> Process {
  let job = Job::spawn_unix(
    path,
    args,
    env~,
    stdin~,
    stdout~,
    stderr~,
    cwd~,
    is_orphan~,
  )
  defer job.0.free()
  let pid = perform_job_in_worker(job.0, context~)
  let pidfd = job.result_handle()
  let handle = if !@fd_util.fd_is_valid(pidfd) {
    None
  } else {
    Some(IoHandle::from_fd(pidfd, kind=Unknown, read_only=true))
  }
  { pid, handle, }
}

///|
#cfg(not(platform="windows"))
fn Process::log_pidfd_eagain_after_readiness(
  self : Process,
  io : IoHandle,
  context : String,
  observed_read_event~ : Bool,
) -> Unit {
  let registration_id = match io.is_async {
    Some(id) => "\{id}"
    None => "None"
  }
  @env_util.eprintln(
    "moonbitlang/async: waitid(P_PIDFD) returned EAGAIN after pidfd readiness; context=\{context}, pid=\{self.pid}, handle=\{io.fd}, registration_id=\{registration_id}, observed_read_event=\{observed_read_event}, read_ready_seq=\{io.read_ready_seq}, last_read_event_mask=\{io.last_read_event_mask}, last_read_event_raw=\{io.last_read_event_raw}",
  )
}

///|
#cfg(not(platform="windows"))
pub async fn Process::wait_pid_unix(self : Process, context~ : String) -> Int {
  guard! curr_loop.val is Some(evloop)
  let handle = if self.handle is Some(io) { io.fd } else { @fd_util.invalid_fd }

  let out = Ref(0)
  let last_wait_observed_read_event = Ref(false)

  if platform is Linux && self.handle is Some(io) {
    let ret = get_process_result(handle, self.pid, out, is_probe=true)
    if ret >= 0 {
      return out.val
    }
    if !@os_error.is_nonblocking_io_error() {
      @os_error.check_errno(context)
    }
    let observed = io.wait_read_observed_event()
    last_wait_observed_read_event.val = observed
  } else if platform is MacOS {
    // MacOS/BSD, use `kqueue` with `EVFILT_PROC`
    if evloop.bus.register_pid(self.pid) {
      evloop.extra.wait_pid(evloop, self.pid)
    }
  } else {
    // Linux systems where pidfd is not available.
    // Fall back to blocking waitpid in worker thread.
    // The thread pool job will obain the exit code and reap the process.
    let job = Job::wait_for_process(handle, pid=self.pid)
    defer job.free()
    return perform_job_in_worker(job, context~, cancellable=true)
  }

  let ret = get_process_result(handle, self.pid, out, is_probe=false)
  if ret < 0 {
    while @os_error.is_nonblocking_io_error() {
      match platform {
        MacOS =>
          // On MacOS, when `kevent` report `ESRCH`,
          // there is a small window where `waitpid(.., WNOHANG)` may still return zero.
          // Work around this race condition by waiting again after a small timeout.
          sleep(10)
        Linux => {
          guard! self.handle is Some(io)
          self.log_pidfd_eagain_after_readiness(
            io,
            context,
            observed_read_event=last_wait_observed_read_event.val,
          )
          let observed = io.wait_read_observed_event()
          last_wait_observed_read_event.val = observed
        }
        Windows => panic()
      }
      let ret = get_process_result(handle, self.pid, out, is_probe=false)
      if ret >= 0 {
        return out.val
      }
    }
    @os_error.check_errno(context)
  }
  out.val
}
