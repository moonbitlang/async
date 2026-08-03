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
#external
priv type Worker

///|
extern "C" fn init_thread_pool_ffi(event_bus : EventBus) -> @fd_util.Fd = "moonbitlang_async_init_thread_pool"

///|
extern "C" fn destroy_thread_pool() = "moonbitlang_async_destroy_thread_pool"

///|
extern "C" fn Worker::spawn(init_job_id : Int, init_job : Job) -> Worker = "moonbitlang_async_spawn_worker"

///|
extern "C" fn Worker::free(worker : Worker) = "moonbitlang_async_free_worker"

///|
extern "C" fn Worker::wake(worker : Worker, job_id : Int, job : Job) = "moonbitlang_async_wake_worker"

///|
extern "C" fn Worker::enter_idle(worker : Worker) = "moonbitlang_async_worker_enter_idle"

///|
extern "C" fn Worker::cancel_ffi(worker : Worker) -> Int = "moonbitlang_async_cancel_worker"

///|
fn Worker::cancel(
  worker : Worker,
  context~ : String,
) -> CancellationStatus raise {
  match worker.cancel_ffi() {
    0 => RetryLater
    1 => NeedWait
    _ => {
      @os_error.check_errno(context)
      NoWait
    }
  }
}

///|
#cfg(not(platform="windows"))
#borrow(output)
extern "C" fn fetch_completion_ffi(
  notify_recv : @fd_util.Fd,
  output : FixedArray[Int],
) -> Int = "moonbitlang_async_fetch_completion"

///|
#external
priv type Job

///|
extern "C" fn Job::free(self : Job) -> Unit = "moonbitlang_async_free_job"

///|
extern "C" fn Job::ret(self : Job) -> Int = "moonbitlang_async_job_get_ret"

///|
extern "C" fn Job::err(self : Job) -> Int = "moonbitlang_async_job_get_err"

///|
/// This is no-op on native, just to align API shape with Wasm.
fn Job::copy_output(self : Job) -> Unit {
  ignore(self)
}

///|
#owned(buf)
extern "C" fn Job::read(
  fd : @fd_util.Fd,
  buf : FixedArray[Byte],
  offset : Int,
  len : Int,
  // `-1` indicates no offset
  position~ : Int64,
) -> Job = "moonbitlang_async_make_read_job"

///|
#owned(buf)
extern "C" fn Job::write(
  fd : @fd_util.Fd,
  buf : Bytes,
  offset : Int,
  len : Int,
  // `-1` indicates no offset
  position~ : Int64,
) -> Job = "moonbitlang_async_make_write_job"

///|
#owned(filename, stat_buf)
extern "C" fn Job::open(
  filename : @os_string.OsString,
  // 0 => read only, 1 => write only, 2 => read write
  access : Int,
  // See `@fs.CreateMode` for more details
  create~ : Int,
  append~ : Bool,
  // 0 => no sync, 1 => data sync, 2 => full sync
  sync~ : Int,
  // permission for file when new file is created
  mode~ : Int,
  stat_request~ : UInt,
  stat_buf~ : FixedArray[Byte],
  stat_buf_len~ : Int,
) -> OpenJob = "moonbitlang_async_make_open_job"

///|
priv struct OpenJob(Job)

///|
extern "C" fn OpenJob::fd(job : OpenJob) -> @fd_util.Fd = "moonbitlang_async_open_job_get_fd"

///|
pub const STAT_FILE_KIND : UInt = 0x0001

///|
pub const STAT_FILE_SIZE : UInt = 0x0002

///|
pub const STAT_DEVICE_ID : UInt = 0x0004

///|
pub const STAT_FILE_ID : UInt = 0x0008

///|
pub const STAT_ACCESS_TIME : UInt = 0x0010

///|
pub const STAT_MODIFY_TIME : UInt = 0x0020

///|
pub const STAT_CHANGE_TIME : UInt = 0x0040

///|
pub const STAT_CREATE_TIME : UInt = 0x0080

///|
#owned(buf)
extern "C" fn Job::fstatx(
  fd : @fd_util.Fd,
  request : UInt,
  buf : FixedArray[Byte],
  buf_len : Int,
) -> Job = "moonbitlang_async_make_fstatx_job"

///|
#owned(path, buf)
extern "C" fn Job::statx(
  path : @os_string.OsString,
  request : UInt,
  buf : FixedArray[Byte],
  buf_len : Int,
  parent~ : @fd_util.Fd,
  follow_symlink~ : Bool,
) -> Job = "moonbitlang_async_make_statx_job"

///|
pub(all) enum Access {
  Exist = 0
  CanRead = 1
  CanWrite = 2
  CanExecute = 3
}

///|
#owned(path)
extern "C" fn Job::access(path : @os_string.OsString, access : Access) -> Job = "moonbitlang_async_make_access_job"

///|
#owned(path)
extern "C" fn Job::chmod(path : @os_string.OsString, mode : Int) -> Job = "moonbitlang_async_make_chmod_job"

///|
extern "C" fn Job::fsync(fd : @fd_util.Fd, only_data : Bool) -> Job = "moonbitlang_async_make_fsync_job"

///|
extern "C" fn Job::flock(fd : @fd_util.Fd, exclusive : Bool) -> Job = "moonbitlang_async_make_flock_job"

///|
#owned(path)
extern "C" fn Job::remove(path : @os_string.OsString) -> Job = "moonbitlang_async_make_remove_job"

///|
#owned(old_path, new_path)
extern "C" fn Job::rename(
  old_path : @os_string.OsString,
  new_path : @os_string.OsString,
  replace~ : Bool,
) -> Job = "moonbitlang_async_make_rename_job"

///|
#owned(target, path)
extern "C" fn Job::symlink(
  target : @os_string.OsString,
  path : @os_string.OsString,
  force_symlink~ : Bool,
) -> Job = "moonbitlang_async_make_symlink_job"

///|
#owned(path)
extern "C" fn Job::mkdir(path : @os_string.OsString, mode : Int) -> Job = "moonbitlang_async_make_mkdir_job"

///|
#owned(path)
extern "C" fn Job::rmdir(path : @os_string.OsString) -> Job = "moonbitlang_async_make_rmdir_job"

///|
extern "C" fn Job::readdir(
  dir : @fd_util.Fd,
  buf : @c_buffer.Buffer,
  len : Int,
  restart : Bool,
) -> Job = "moonbitlang_async_make_readdir_job"

///|
#owned(path)
extern "C" fn Job::realpath(path : @os_string.OsString) -> Job = "moonbitlang_async_make_realpath_job"

///|
extern "C" fn Job::get_realpath_result(job : Job) -> @c_buffer.Buffer = "moonbitlang_async_get_realpath_result"

///|
priv struct SpawnJob(Job)

///|
#cfg(not(platform="windows"))
#owned(path, args, env)
extern "C" fn Job::spawn_unix_ffi(
  path : @os_string.OsString,
  args : @c_buffer.Buffer,
  env~ : @c_buffer.Buffer,
  stdin~ : @fd_util.Fd,
  stdout~ : @fd_util.Fd,
  stderr~ : @fd_util.Fd,
  is_orphan~ : Bool,
) -> SpawnJob = "moonbitlang_async_make_spawn_job"

///|
#cfg(platform="windows")
#owned(command_line, env)
extern "C" fn Job::spawn_windows_ffi(
  command_line : @os_string.OsString,
  env~ : @c_buffer.Buffer,
  stdin~ : @fd_util.Fd,
  stdout~ : @fd_util.Fd,
  stderr~ : @fd_util.Fd,
  is_orphan~ : Bool,
) -> SpawnJob = "moonbitlang_async_make_spawn_job"

///|
#borrow(job)
#owned(cwd)
extern "C" fn SpawnJob::set_cwd(job : SpawnJob, cwd : @os_string.OsString) = "moonbitlang_async_spawn_job_set_cwd"

///|
#cfg(platform="windows")
#borrow(job)
extern "C" fn SpawnJob::set_no_console_window(job : SpawnJob) = "moonbitlang_async_spawn_job_set_no_console_window"

///|
extern "C" fn SpawnJob::result_handle(job : SpawnJob) -> @fd_util.Fd = "moonbitlang_async_get_spawn_job_result_handle"

///|
#cfg(not(platform="windows"))
fn Job::spawn_unix(
  path : @os_string.OsString,
  args : @c_buffer.Buffer,
  env~ : @c_buffer.Buffer,
  stdin~ : @fd_util.Fd,
  stdout~ : @fd_util.Fd,
  stderr~ : @fd_util.Fd,
  is_orphan~ : Bool,
  cwd~ : @os_string.OsString?,
) -> SpawnJob {
  let job = Job::spawn_unix_ffi(
    path,
    args,
    env~,
    stdin~,
    stdout~,
    stderr~,
    is_orphan~,
  )
  if cwd is Some(cwd) {
    job.set_cwd(cwd)
  }
  job
}

///|
#cfg(platform="windows")
fn Job::spawn_windows(
  command_line : @os_string.OsString,
  env~ : @c_buffer.Buffer,
  stdin~ : @fd_util.Fd,
  stdout~ : @fd_util.Fd,
  stderr~ : @fd_util.Fd,
  is_orphan~ : Bool,
  cwd~ : @os_string.OsString?,
  no_console_window~ : Bool,
) -> SpawnJob {
  let job = Job::spawn_windows_ffi(
    command_line,
    env~,
    stdin~,
    stdout~,
    stderr~,
    is_orphan~,
  )
  if cwd is Some(cwd) {
    job.set_cwd(cwd)
  }
  if no_console_window {
    job.set_no_console_window()
  }
  job
}

///|
// `handle` is used by Windows, `pid` is used by Linux
extern "C" fn Job::wait_for_process(handle : @fd_util.Fd, pid~ : Int) -> Job = "moonbitlang_async_make_wait_for_process_job"

///|
#owned(addr)
extern "C" fn Job::bind(socket : @fd_util.Fd, addr : Bytes) -> Job = "moonbitlang_async_make_bind_job"

///|
#owned(host)
extern "C" fn Job::getaddrinfo(host : @os_string.OsString) -> Job = "moonbitlang_async_make_getaddrinfo_job"

///|
extern "C" fn Job::get_getaddrinfo_result(job : Job) -> AddrInfo = "moonbitlang_async_get_getaddrinfo_result"

///|
#cfg(not(platform="windows"))
#borrow(signals)
extern "C" fn Job::sigwait(signals : ReadOnlyArray[Int]) -> Job = "moonbitlang_async_make_sigwait_job"

///|
#cfg(not(platform="windows"))
#owned(path)
extern "C" fn Job::inotify_add_watch(
  inotify : @fd_util.Fd,
  path : @os_string.OsString,
  is_dir : Bool,
) -> Job = "moonbitlang_async_make_inotify_add_watch_job"
