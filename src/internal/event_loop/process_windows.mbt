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
#cfg(platform="windows")
extern "C" fn init_global_job_object_ffi() -> Bool = "moonbitlang_async_init_global_job_objeect"

///|
#cfg(platform="windows")
let global_job_object_initialized : Ref[Bool] = Ref(false)

///|
#cfg(platform="windows")
fn init_global_job_object() -> Unit raise {
  guard global_job_object_initialized.val is false else {  }
  global_job_object_initialized.val = true
  if !init_global_job_object_ffi() {
    @os_error.check_errno("create global job object")
  }
}

///|
#cfg(platform="windows")
pub async fn spawn(
  command_line : @os_string.OsString,
  env~ : @c_buffer.Buffer,
  stdin~ : @fd_util.Fd,
  stdout~ : @fd_util.Fd,
  stderr~ : @fd_util.Fd,
  cwd~ : @os_string.OsString?,
  no_console_window~ : Bool,
  is_orphan~ : Bool,
  context~ : String,
) -> Process {
  init_global_job_object()
  let job = Job::spawn(
    command_line,
    env,
    stdin,
    stdout,
    stderr,
    cwd,
    no_console_window~,
    is_orphan~,
  )
  defer job.0.free()
  let pid = perform_job_in_worker(job.0, context~)
  let handle = IoHandle::from_fd(
    job.result_handle(),
    kind=Unknown,
    is_async=false,
  )
  { pid, handle: Some(handle) }
}

///|
#cfg(platform="windows")
pub async fn Process::wait_pid(self : Process, context~ : String) -> Int {
  guard self.handle is Some(io)
  let job = Job::wait_for_process(io.fd)
  defer job.free()
  let _ = perform_job_in_worker(job, context~, cancel=_ => {
    job.cancel_process_waiter()
    NeedWait
  })

  let out = Ref(0)
  let ret = get_process_result(io.fd, self.pid, out)
  if ret < 0 {
    @os_error.check_errno(context)
  }
  out.val
}
