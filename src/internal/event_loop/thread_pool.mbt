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
extern "C" fn init_thread_pool_ffi(notify_send : Int) = "moonbitlang_async_init_thread_pool"

///|
extern "C" fn destroy_thread_pool() = "moonbitlang_async_destroy_thread_pool"

///|
#owned(init_job)
extern "C" fn spawn_worker(init_job : Job) -> Worker = "moonbitlang_async_spawn_worker"

///|
#borrow(worker)
#owned(job)
extern "C" fn wake_worker(worker : Worker, job : Job) = "moonbitlang_async_wake_worker"

///|
extern "C" fn fetch_completion_ffi(notify_recv : Int) -> Int = "moonbitlang_async_fetch_completion"

///|
priv type Job

///|
#borrow(self)
extern "C" fn Job::id(self : Job) -> Int = "moonbitlang_async_job_get_id"

///|
#borrow(self)
extern "C" fn Job::ret(self : Job) -> Int = "moonbitlang_async_job_get_ret"

///|
#borrow(self)
extern "C" fn Job::err(self : Job) -> Int = "moonbitlang_async_job_get_err"

///|
#owned(buf)
extern "C" fn Job::read(
  fd : Int,
  buf : FixedArray[Byte],
  offset : Int,
  len : Int,
) -> Job = "moonbitlang_async_make_read_job"

///|
#owned(buf)
extern "C" fn Job::write(fd : Int, buf : Bytes, offset : Int, len : Int) -> Job = "moonbitlang_async_make_write_job"

///|
#owned(filename, stat)
extern "C" fn Job::open(
  filename : Bytes,
  flags : Int,
  mode : Int,
  stat : @fd_util.Stat,
) -> Job = "moonbitlang_async_make_open_job"

///|
#owned(path, out)
extern "C" fn Job::stat(
  path : Bytes,
  out : @fd_util.Stat,
  follow_symlink~ : Bool,
) -> Job = "moonbitlang_async_make_stat_job"

///|
#owned(out)
extern "C" fn Job::fstat(fd : Int, out : @fd_util.Stat) -> Job = "moonbitlang_async_make_fstat_job"

///|
extern "C" fn Job::seek(fd : Int, offset : Int64, whence : Int) -> Job = "moonbitlang_async_make_seek_job"

///|
#borrow(job)
extern "C" fn Job::get_seek_result(job : Job) -> Int64 = "moonbitlang_async_get_seek_result"

///|
#owned(path)
extern "C" fn Job::access(path : Bytes, amode : Int) -> Job = "moonbitlang_async_make_access_job"

///|
extern "C" fn Job::fsync(fd : Int, only_data : Bool) -> Job = "moonbitlang_async_make_fsync_job"

///|
#owned(path)
extern "C" fn Job::remove(path : Bytes) -> Job = "moonbitlang_async_make_remove_job"

///|
#owned(target, path)
extern "C" fn Job::symlink(target : Bytes, path : Bytes) -> Job = "moonbitlang_async_make_symlink_job"

///|
#owned(path)
extern "C" fn Job::mkdir(path : Bytes, mode : Int) -> Job = "moonbitlang_async_make_mkdir_job"

///|
#owned(path)
extern "C" fn Job::rmdir(path : Bytes) -> Job = "moonbitlang_async_make_rmdir_job"

///|
#owned(path)
extern "C" fn Job::opendir(path : Bytes) -> Job = "moonbitlang_async_make_opendir_job"

///|
#borrow(job)
extern "C" fn Job::get_opendir_result(job : Job) -> Directory = "moonbitlang_async_get_opendir_result"

///|
extern "C" fn Job::readdir(dir : Directory) -> Job = "moonbitlang_async_make_readdir_job"

///|
#borrow(job)
extern "C" fn Job::get_readdir_result(job : Job) -> DirectoryEntry = "moonbitlang_async_get_readdir_result"

///|
#owned(path)
extern "C" fn Job::realpath(path : Bytes) -> Job = "moonbitlang_async_make_realpath_job"

///|
#borrow(job)
extern "C" fn Job::get_realpath_result(job : Job) -> @c_buffer.Buffer = "moonbitlang_async_get_realpath_result"

///|
#owned(path, args, env, cwd)
extern "C" fn Job::spawn(
  path : Bytes,
  args : FixedArray[Bytes?],
  env : FixedArray[Bytes?],
  stdin : Int,
  stdout : Int,
  stderr : Int,
  cwd : Bytes?,
) -> Job = "moonbitlang_async_make_spawn_job"

///|
#owned(host)
extern "C" fn Job::getaddrinfo(host : Bytes) -> Job = "moonbitlang_async_make_getaddrinfo_job"

///|
#borrow(job)
extern "C" fn Job::get_getaddrinfo_result(job : Job) -> AddrInfo = "moonbitlang_async_get_getaddrinfo_result"
