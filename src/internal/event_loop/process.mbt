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
pub async fn spawn(
  path : @os_string.OsString,
  args : FixedArray[@os_string.OsString?],
  env~ : FixedArray[@os_string.OsString?],
  stdin~ : @fd_util.Fd,
  stdout~ : @fd_util.Fd,
  stderr~ : @fd_util.Fd,
  cwd~ : @os_string.OsString?,
  context~ : String,
) -> Int {
  perform_job_in_worker(
    Job::spawn(path, args, env, stdin, stdout, stderr, cwd),
    context~,
  )
}

///|
#cfg(platform="windows")
pub async fn spawn(
  command_line : @os_string.OsString,
  env~ : @os_string.OsString?,
  stdin~ : @fd_util.Fd,
  stdout~ : @fd_util.Fd,
  stderr~ : @fd_util.Fd,
  cwd~ : @os_string.OsString?,
  context~ : String,
) -> Int {
  perform_job_in_worker(
    Job::spawn(command_line, env, stdin, stdout, stderr, cwd),
    context~,
  )
}

///|
#cfg(not(platform="windows"))
pub async fn wait_pid(pid : Int, context~ : String) -> Unit {
  guard curr_loop.val is Some(evloop)
  ignore(context)
  let alt_id = match evloop.poll.register_pid(pid) {
    Running(id) => id
    Stopped => return
  }
  guard evloop.pids.get(alt_id) is None
  evloop.pids[alt_id] = @coroutine.current_coroutine()
  defer {
    evloop.pids.remove(alt_id)
    evloop.poll.remove_pid(alt_id)
  }
  @coroutine.suspend()
}

///|
#cfg(platform="windows")
pub async fn wait_pid(pid : Int, context~ : String) -> Unit {
  let job = Job::wait_for_process(pid)
  perform_job_in_worker(job, context~, cancel=_ => {
    job.cancel_process_waiter()
    NeedWait
  })
  |> ignore
}
