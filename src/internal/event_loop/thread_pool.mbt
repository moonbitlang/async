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
extern "C" fn spawn_worker(init_job : JobForWorker) -> Worker = "moonbitlang_async_spawn_worker"

///|
#borrow(worker)
#owned(job)
extern "C" fn wake_worker(worker : Worker, job : JobForWorker) = "moonbitlang_async_wake_worker"

///|
extern "C" fn fetch_completion_ffi(notify_recv : Int) -> Int = "moonbitlang_async_fetch_completion"

///|
priv type JobForWorker

///|
#borrow(self)
extern "C" fn JobForWorker::id(self : JobForWorker) -> Int = "moonbitlang_async_job_get_id"

///|
#borrow(self)
extern "C" fn JobForWorker::ret(self : JobForWorker) -> Int = "moonbitlang_async_job_get_ret"

///|
#borrow(self)
extern "C" fn JobForWorker::err(self : JobForWorker) -> Int = "moonbitlang_async_job_get_err"

///|
#owned(buf)
extern "C" fn JobForWorker::read(
  fd : Int,
  buf : FixedArray[Byte],
  offset : Int,
  len : Int,
) -> JobForWorker = "moonbitlang_async_make_read_job"

///|
#owned(buf)
extern "C" fn JobForWorker::write(
  fd : Int,
  buf : Bytes,
  offset : Int,
  len : Int,
) -> JobForWorker = "moonbitlang_async_make_write_job"

///|
#owned(filename)
extern "C" fn JobForWorker::open(
  filename : Bytes,
  flags : Int,
  mode : Int,
) -> JobForWorker = "moonbitlang_async_make_open_job"

///|
#owned(path, out)
extern "C" fn JobForWorker::stat(
  path : Bytes,
  out : @fd_util.Stat,
  follow_symlink~ : Bool,
) -> JobForWorker = "moonbitlang_async_make_stat_job"

///|
#owned(out)
extern "C" fn JobForWorker::fstat(
  fd : Int,
  out : @fd_util.Stat,
) -> JobForWorker = "moonbitlang_async_make_fstat_job"

///|
#owned(out)
extern "C" fn JobForWorker::seek(
  fd : Int,
  offset : Int64,
  whence : Int,
  out : Ref[Int64],
) -> JobForWorker = "moonbitlang_async_make_seek_job"

///|
#owned(path)
extern "C" fn JobForWorker::access(path : Bytes, amode : Int) -> JobForWorker = "moonbitlang_async_make_access_job"

///|
extern "C" fn JobForWorker::fsync(fd : Int, only_data : Bool) -> JobForWorker = "moonbitlang_async_make_fsync_job"

///|
#owned(path)
extern "C" fn JobForWorker::remove(path : Bytes) -> JobForWorker = "moonbitlang_async_make_remove_job"

///|
#owned(path)
extern "C" fn JobForWorker::mkdir(path : Bytes, mode : Int) -> JobForWorker = "moonbitlang_async_make_mkdir_job"

///|
#owned(path)
extern "C" fn JobForWorker::rmdir(path : Bytes) -> JobForWorker = "moonbitlang_async_make_rmdir_job"

///|
#owned(out)
extern "C" fn JobForWorker::readdir(
  dir : Directory,
  out : Ref[DirectoryEntry],
) -> JobForWorker = "moonbitlang_async_make_readdir_job"

///|
#owned(path, out)
extern "C" fn JobForWorker::realpath(
  path : Bytes,
  out : Ref[@c_buffer.Buffer],
) -> JobForWorker = "moonbitlang_async_make_realpath_job"

///|
#owned(path, args, env, cwd)
extern "C" fn JobForWorker::spawn(
  path : Bytes,
  args : FixedArray[Bytes?],
  env : FixedArray[Bytes?],
  stdin : Int,
  stdout : Int,
  stderr : Int,
  cwd : Bytes?,
) -> JobForWorker = "moonbitlang_async_make_spawn_job"

///|
#owned(host, out)
extern "C" fn JobForWorker::getaddrinfo(
  host : Bytes,
  out : AddrInfoRef,
) -> JobForWorker = "moonbitlang_async_make_getaddrinfo_job"
