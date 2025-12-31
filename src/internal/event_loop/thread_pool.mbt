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
priv type Worker

///|
extern "C" fn init_thread_pool_ffi(notify_send : @fd_util.Fd) = "moonbitlang_async_init_thread_pool"

///|
extern "C" fn destroy_thread_pool() = "moonbitlang_async_destroy_thread_pool"

///|
#owned(init_job)
extern "C" fn spawn_worker(init_job_id : Int, init_job : Job) -> Worker = "moonbitlang_async_spawn_worker"

///|
#borrow(worker)
#owned(job)
extern "C" fn wake_worker(worker : Worker, job_id : Int, job : Job) = "moonbitlang_async_wake_worker"

///|
#cfg(not(platform="windows"))
extern "C" fn fetch_completion_ffi(notify_recv : @fd_util.Fd) -> Int = "moonbitlang_async_fetch_completion"

///|
priv type Job

///|
#borrow(self)
extern "C" fn Job::ret(self : Job) -> Int = "moonbitlang_async_job_get_ret"

///|
#borrow(self)
extern "C" fn Job::err(self : Job) -> Int = "moonbitlang_async_job_get_err"

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
#owned(filename)
extern "C" fn Job::open(
  filename : @os_string.OsString,
  // 0 => read only, 1 => write only, 2 => read write
  access : Int,
  create~ : Bool,
  append~ : Bool,
  truncate~ : Bool,
  // 0 => no sync, 1 => data sync, 2 => full sync
  sync~ : Int,
  // permission for file when new file is created
  mode~ : Int,
  is_async~ : Bool,
) -> Job = "moonbitlang_async_make_open_job"

///|
#borrow(job)
extern "C" fn Job::get_open_job_result(job : Job) -> @fd_util.Fd = "moonbitlang_async_get_open_job_result"

///|
#borrow(job)
extern "C" fn Job::get_open_job_kind(job : Job) -> Int64 = "moonbitlang_async_get_open_job_kind"

///|
#owned(path)
extern "C" fn Job::file_kind_by_path(
  path : @os_string.OsString,
  follow_symlink~ : Bool,
) -> Job = "moonbitlang_async_make_file_kind_by_path_job"

///|
#borrow(job)
extern "C" fn Job::get_file_kind_by_path_result(job : Job) -> Int64 = "moonbitlang_async_get_file_kind_by_path_result"

///|
extern "C" fn Job::file_size(fd : @fd_util.Fd) -> Job = "moonbitlang_async_make_file_size_job"

///|
#borrow(job)
extern "C" fn Job::get_file_size_result(job : Job) -> Int64 = "moonbitlang_async_get_file_size_result"

///|
#owned(out)
extern "C" fn Job::file_time(fd : @fd_util.Fd, out : @fd_util.FileTime) -> Job = "moonbitlang_async_make_file_time_job"

///|
#owned(path, out)
extern "C" fn Job::file_time_by_path(
  path : @os_string.OsString,
  out : @fd_util.FileTime,
  follow_symlink~ : Bool,
) -> Job = "moonbitlang_async_make_file_time_by_path_job"

///|
#owned(path)
extern "C" fn Job::access(path : @os_string.OsString, amode : Int) -> Job = "moonbitlang_async_make_access_job"

///|
#owned(path)
extern "C" fn Job::chmod(path : @os_string.OsString, mode : Int) -> Job = "moonbitlang_async_make_chmod_job"

///|
extern "C" fn Job::fsync(fd : @fd_util.Fd, only_data : Bool) -> Job = "moonbitlang_async_make_fsync_job"

///|
#owned(path)
extern "C" fn Job::remove(path : @os_string.OsString) -> Job = "moonbitlang_async_make_remove_job"

///|
#owned(target, path)
extern "C" fn Job::symlink(
  target : @os_string.OsString,
  path : @os_string.OsString,
) -> Job = "moonbitlang_async_make_symlink_job"

///|
#owned(path)
extern "C" fn Job::mkdir(path : @os_string.OsString, mode : Int) -> Job = "moonbitlang_async_make_mkdir_job"

///|
#owned(path)
extern "C" fn Job::rmdir(path : @os_string.OsString) -> Job = "moonbitlang_async_make_rmdir_job"

///|
#owned(path)
extern "C" fn Job::opendir(path : @os_string.OsString) -> Job = "moonbitlang_async_make_opendir_job"

///|
#borrow(job)
extern "C" fn Job::get_opendir_result(job : Job) -> Directory = "moonbitlang_async_get_opendir_result"

///|
extern "C" fn Job::readdir(dir : Directory) -> Job = "moonbitlang_async_make_readdir_job"

///|
#borrow(job)
extern "C" fn Job::get_readdir_result(job : Job) -> @c_buffer.Buffer = "moonbitlang_async_get_readdir_result"

///|
#owned(path)
extern "C" fn Job::realpath(path : @os_string.OsString) -> Job = "moonbitlang_async_make_realpath_job"

///|
#cfg(not(platform="windows"))
#borrow(job)
extern "C" fn Job::get_realpath_result(job : Job) -> @c_buffer.Buffer = "moonbitlang_async_get_realpath_result"

///|
#cfg(platform="windows")
#borrow(job)
extern "C" fn Job::get_realpath_result(job : Job) -> String = "moonbitlang_async_get_realpath_result"

///|
#cfg(not(platform="windows"))
#owned(path, args, env, cwd)
extern "C" fn Job::spawn(
  path : @os_string.OsString,
  args : FixedArray[@os_string.OsString?],
  env : FixedArray[@os_string.OsString?],
  stdin : @fd_util.Fd,
  stdout : @fd_util.Fd,
  stderr : @fd_util.Fd,
  cwd : @os_string.OsString?,
) -> Job = "moonbitlang_async_make_spawn_job"

///|
#cfg(platform="windows")
#owned(command_line, env, cwd)
extern "C" fn Job::spawn(
  command_line : @os_string.OsString,
  env : @os_string.OsString?,
  stdin : @fd_util.Fd,
  stdout : @fd_util.Fd,
  stderr : @fd_util.Fd,
  cwd : @os_string.OsString?,
) -> Job = "moonbitlang_async_make_spawn_job"

///|
#cfg(platform="windows")
extern "C" fn Job::wait_for_process(pid : Int) -> Job = "moonbitlang_async_make_wait_for_process_job"

///|
#cfg(platform="windows")
#borrow(job)
extern "C" fn Job::cancel_process_waiter(job : Job) = "moonbitlang_async_cancel_wait_for_process_job"

///|
#owned(host)
extern "C" fn Job::getaddrinfo(host : @os_string.OsString) -> Job = "moonbitlang_async_make_getaddrinfo_job"

///|
#borrow(job)
extern "C" fn Job::get_getaddrinfo_result(job : Job) -> AddrInfo = "moonbitlang_async_get_getaddrinfo_result"
