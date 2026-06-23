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
priv struct Worker(UInt64)

///|
#unsafe_skip_stub_check
fn init_thread_pool_ffi(bus : EventBus) -> @fd_util.Fd = "moonbitlang/async" "thread_pool/init_thread_pool"

///|
#unsafe_skip_stub_check
fn destroy_thread_pool() -> Unit = "moonbitlang/async" "thread_pool/destroy_thread_pool"

///|
#unsafe_skip_stub_check
fn Worker::spawn(init_job_id : Int, init_job : Job) -> Worker = "moonbitlang/async" "thread_pool/spawn_worker"

///|
#unsafe_skip_stub_check
fn Worker::free(worker : Worker) -> Unit = "moonbitlang/async" "thread_pool/free_worker"

///|
#unsafe_skip_stub_check
fn Worker::wake(worker : Worker, job_id : Int, job : Job) -> Unit = "moonbitlang/async" "thread_pool/wake_worker"

///|
#unsafe_skip_stub_check
fn Worker::enter_idle(worker : Worker) -> Unit = "moonbitlang/async" "thread_pool/worker_enter_idle"

///|
#unsafe_skip_stub_check
fn Worker::cancel_ffi(worker : Worker) -> Int = "moonbitlang/async" "thread_pool/cancel_worker"

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
#unsafe_skip_stub_check
#borrow(output)
fn fetch_completion_ffi(
  notify_recv : @fd_util.Fd,
  output : FixedArray[Int],
  len? : Int = output.length(),
) -> Int = "moonbitlang/async" "thread_pool/fetch_completion/unix"

///|
priv struct Job(UInt64)

///|
#unsafe_skip_stub_check
fn Job::free(self : Job) -> Unit = "moonbitlang/async" "thread_pool/free_job"

///|
#unsafe_skip_stub_check
fn Job::ret(self : Job) -> Int = "moonbitlang/async" "thread_pool/job_get_ret"

///|
#unsafe_skip_stub_check
fn Job::err(self : Job) -> Int = "moonbitlang/async" "thread_pool/job_get_err"

///|
#unsafe_skip_stub_check
fn Job::read(fd : @fd_util.Fd, len : Int, position~ : Int64) -> Job = "moonbitlang/async" "thread_pool/make_read_job"

///|
#unsafe_skip_stub_check
#borrow(buf)
fn Job::get_read_result(
  self : Job,
  buf : FixedArray[Byte],
  offset : Int,
  len : Int,
) -> Unit = "moonbitlang/async" "thread_pool/get_read_result"

///|
#unsafe_skip_stub_check
#borrow(buf)
fn Job::write(
  fd : @fd_util.Fd,
  buf : Bytes,
  offset : Int,
  len : Int,
  // `-1` indicates no offset
  position~ : Int64,
) -> Job = "moonbitlang/async" "thread_pool/make_write_job"

///|
#unsafe_skip_stub_check
#borrow(filename)
fn Job::open(
  filename : @os_string.OsString,
  filename_len? : Int = filename.to_string().length(),
  // 0 => read only, 1 => write only, 2 => read write
  access : Int,
  // See `@fs.CreateMode` for more details
  create~ : Int,
  append~ : Bool,
  // 0 => no sync, 1 => data sync, 2 => full sync
  sync~ : Int,
  // permission for file when new file is created
  mode~ : Int,
) -> OpenJob = "moonbitlang/async" "thread_pool/make_open_job"

///|
priv struct OpenJob(Job)

///|
#unsafe_skip_stub_check
fn OpenJob::fd(job : OpenJob) -> @fd_util.Fd = "moonbitlang/async" "thread_pool/open_job_get_fd"

///|
#unsafe_skip_stub_check
fn OpenJob::kind(job : OpenJob) -> @fd_util.FileKind = "moonbitlang/async" "thread_pool/open_job_get_kind"

///|
#unsafe_skip_stub_check
fn OpenJob::dev_id(job : OpenJob) -> UInt64 = "moonbitlang/async" "thread_pool/open_job_get_dev_id"

///|
#unsafe_skip_stub_check
fn OpenJob::file_id(job : OpenJob) -> UInt64 = "moonbitlang/async" "thread_pool/open_job_get_file_id"

///|
#unsafe_skip_stub_check
#borrow(path)
fn Job::file_kind_by_path(
  parent : @fd_util.Fd,
  path : @os_string.OsString,
  path_len? : Int = path.to_string().length(),
  follow_symlink~ : Bool,
) -> Job = "moonbitlang/async" "thread_pool/make_file_kind_by_path_job"

///|
#unsafe_skip_stub_check
fn Job::file_size(fd : @fd_util.Fd) -> Job = "moonbitlang/async" "thread_pool/make_file_size_job"

///|
#unsafe_skip_stub_check
fn Job::get_file_size_result(job : Job) -> Int64 = "moonbitlang/async" "thread_pool/get_file_size_result"

///|
#unsafe_skip_stub_check
fn Job::file_time(fd : @fd_util.Fd) -> Job = "moonbitlang/async" "thread_pool/make_file_time_job"

///|
#unsafe_skip_stub_check
#borrow(path)
fn Job::file_time_by_path(
  path : @os_string.OsString,
  path_len? : Int = path.to_string().length(),
  follow_symlink~ : Bool,
) -> Job = "moonbitlang/async" "thread_pool/make_file_time_by_path_job"

///|
#unsafe_skip_stub_check
#borrow(out)
fn Job::get_file_time_result(self : Job, out : @fd_util.FileTime) -> Unit = "moonbitlang/async" "thread_pool/get_file_time_result"

///|
pub(all) enum Access {
  Exist = 0
  CanRead = 1
  CanWrite = 2
  CanExecute = 3
}

///|
#unsafe_skip_stub_check
#borrow(path)
fn Job::access(
  path : @os_string.OsString,
  path_len? : Int = path.to_string().length(),
  access : Access,
) -> Job = "moonbitlang/async" "thread_pool/make_access_job"

///|
#unsafe_skip_stub_check
#borrow(path)
fn Job::chmod(
  path : @os_string.OsString,
  path_len? : Int = path.to_string().length(),
  mode : Int,
) -> Job = "moonbitlang/async" "thread_pool/make_chmod_job"

///|
#unsafe_skip_stub_check
fn Job::fsync(fd : @fd_util.Fd, only_data : Bool) -> Job = "moonbitlang/async" "thread_pool/make_fsync_job"

///|
#unsafe_skip_stub_check
fn Job::flock(fd : @fd_util.Fd, exclusive : Bool) -> Job = "moonbitlang/async" "thread_pool/make_flock_job"

///|
#unsafe_skip_stub_check
#borrow(path)
fn Job::remove(
  path : @os_string.OsString,
  path_len? : Int = path.to_string().length(),
) -> Job = "moonbitlang/async" "thread_pool/make_remove_job"

///|
#unsafe_skip_stub_check
#borrow(old_path, new_path)
fn Job::rename(
  old_path : @os_string.OsString,
  old_path_len? : Int = old_path.to_string().length(),
  new_path : @os_string.OsString,
  new_path_len? : Int = new_path.to_string().length(),
  replace~ : Bool,
) -> Job = "moonbitlang/async" "thread_pool/make_rename_job"

///|
#unsafe_skip_stub_check
#borrow(target, path)
fn Job::symlink(
  target : @os_string.OsString,
  target_len? : Int = target.to_string().length(),
  path : @os_string.OsString,
  path_len? : Int = path.to_string().length(),
  force_symlink~ : Bool,
) -> Job = "moonbitlang/async" "thread_pool/make_symlink_job"

///|
#unsafe_skip_stub_check
#borrow(path)
fn Job::mkdir(
  path : @os_string.OsString,
  path_len? : Int = path.to_string().length(),
  mode : Int,
) -> Job = "moonbitlang/async" "thread_pool/make_mkdir_job"

///|
#unsafe_skip_stub_check
#borrow(path)
fn Job::rmdir(
  path : @os_string.OsString,
  path_len? : Int = path.to_string().length(),
) -> Job = "moonbitlang/async" "thread_pool/make_rmdir_job"

///|
#unsafe_skip_stub_check
#borrow(buf)
fn Job::readdir(
  dir : @fd_util.Fd,
  buf : @c_buffer.Buffer,
  len : Int,
  restart : Bool,
) -> Job = "moonbitlang/async" "thread_pool/make_readdir_job"

// Job::realpath

// Job::get_realpath_result
