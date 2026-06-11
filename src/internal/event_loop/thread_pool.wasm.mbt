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
priv struct Worker(Int)

///|
fn init_thread_pool_ffi(_notify_send : @fd_util.Fd) -> Unit {
  ()
}

///|
fn destroy_thread_pool() -> Unit {
  ()
}

///|
fn spawn_worker_ffi(init_job_id : Int, init_job : Int) -> Int = "moonbit_v0" "spawn_worker"

///|
fn free_worker_ffi(worker : Int) -> Unit = "moonbit_v0" "free_worker"

///|
fn wake_worker_ffi(worker : Int, job_id : Int, job : Int) -> Unit = "moonbit_v0" "wake_worker"

///|
fn worker_enter_idle_ffi(worker : Int) -> Unit = "moonbit_v0" "worker_enter_idle"

///|
fn cancel_worker_ffi(worker : Int) -> Int = "moonbit_v0" "cancel_worker"

///|
fn fetch_completion_raw(output : Int, len : Int) -> Int = "moonbit_v0" "fetch_completion"

///|
#borrow(array)
fn int_array_to_ptr(array : FixedArray[Int]) -> Int =
  #|(func (param i32) (result i32) local.get 0)

///|
fn fetch_completion_ffi(output : FixedArray[Int]) -> Int {
  fetch_completion_raw(int_array_to_ptr(output), output.length())
}

///|
fn Worker::spawn(init_job_id : Int, init_job : Job) -> Worker {
  Worker(spawn_worker_ffi(init_job_id, init_job.handle))
}

///|
fn Worker::free(worker : Worker) -> Unit {
  free_worker_ffi(worker.0)
}

///|
fn Worker::wake(worker : Worker, job_id : Int, job : Job) -> Unit {
  wake_worker_ffi(worker.0, job_id, job.handle)
}

///|
fn Worker::enter_idle(worker : Worker) -> Unit {
  worker_enter_idle_ffi(worker.0)
}

///|
fn Worker::cancel_ffi(worker : Worker) -> Int {
  cancel_worker_ffi(worker.0)
}

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
priv struct Job {
  handle : Int
  read_buf : FixedArray[Byte]?
  write_buf : Bytes?
  path : @os_string.OsString?
}

///|
fn free_job_ffi(job : Int) -> Unit = "moonbit_v0" "free_job"

///|
fn run_job_ffi(job : Int) -> Unit = "moonbit_v0" "run_job"

///|
fn complete_job_ffi(job : Int) -> Unit = "moonbit_v0" "complete_job"

///|
fn job_get_ret_ffi(job : Int) -> Int = "moonbit_v0" "job_get_ret"

///|
fn job_get_err_ffi(job : Int) -> Int = "moonbit_v0" "job_get_err"

///|
fn make_read_job_ffi(
  fd : @fd_util.Fd,
  buf : Int,
  offset : Int,
  len : Int,
  position : Int64,
) -> Int = "moonbit_v0" "make_read_job"

///|
fn make_write_job_ffi(
  fd : @fd_util.Fd,
  buf : Int,
  offset : Int,
  len : Int,
  position : Int64,
) -> Int = "moonbit_v0" "make_write_job"

///|
fn make_open_job_ffi(
  filename : Int,
  filename_len : Int,
  access : Int,
  create : Int,
  append : Bool,
  sync : Int,
  mode : Int,
) -> Int = "moonbit_v0" "make_open_job"

///|
fn open_job_get_fd_ffi(job : Int) -> @fd_util.Fd = "moonbit_v0" "open_job_get_fd"

///|
fn open_job_get_kind_ffi(job : Int) -> @fd_util.FileKind = "moonbit_v0" "open_job_get_kind"

///|
fn open_job_get_dev_id_ffi(job : Int) -> UInt64 = "moonbit_v0" "open_job_get_dev_id"

///|
fn open_job_get_file_id_ffi(job : Int) -> UInt64 = "moonbit_v0" "open_job_get_file_id"

///|
fn Job::free(self : Job) -> Unit {
  free_job_ffi(self.handle)
}

///|
fn Job::run(self : Job) -> Unit {
  run_job_ffi(self.handle)
}

///|
fn Job::complete(self : Job) -> Unit {
  complete_job_ffi(self.handle)
}

///|
fn Job::ret(self : Job) -> Int {
  job_get_ret_ffi(self.handle)
}

///|
fn Job::err(self : Job) -> Int {
  job_get_err_ffi(self.handle)
}

///|
fn Job::read(
  fd : @fd_util.Fd,
  buf : FixedArray[Byte],
  offset : Int,
  len : Int,
  position~ : Int64,
) -> Job {
  {
    handle: make_read_job_ffi(
      fd,
      @wasm_ffi.byte_array_to_ptr(buf),
      offset,
      len,
      position,
    ),
    read_buf: Some(buf),
    write_buf: None,
    path: None,
  }
}

///|
fn Job::write(
  fd : @fd_util.Fd,
  buf : Bytes,
  offset : Int,
  len : Int,
  position~ : Int64,
) -> Job {
  {
    handle: make_write_job_ffi(
      fd,
      @wasm_ffi.bytes_to_ptr(buf),
      offset,
      len,
      position,
    ),
    read_buf: None,
    write_buf: Some(buf),
    path: None,
  }
}

///|
fn Job::open(
  filename : @os_string.OsString,
  access : Int,
  create~ : Int,
  append~ : Bool,
  sync~ : Int,
  mode~ : Int,
) -> OpenResult {
  let encoded = @utf8.encode(filename.to_string())
  let job = {
    handle: make_open_job_ffi(
      @wasm_ffi.bytes_to_ptr(encoded),
      encoded.length(),
      access,
      create,
      append,
      sync,
      mode,
    ),
    read_buf: None,
    write_buf: Some(encoded),
    path: Some(filename),
  }
  OpenResult(job)
}

///|
struct OpenResult(Job)

///|
priv struct OpenJob(Job)

///|
fn OpenResult::fd(job : OpenResult) -> @fd_util.Fd {
  open_job_get_fd_ffi(job.0.handle)
}

///|
fn OpenResult::kind(job : OpenResult) -> @fd_util.FileKind {
  open_job_get_kind_ffi(job.0.handle)
}

///|
fn OpenResult::dev_id(job : OpenResult) -> UInt64 {
  open_job_get_dev_id_ffi(job.0.handle)
}

///|
fn OpenResult::file_id(job : OpenResult) -> UInt64 {
  open_job_get_file_id_ffi(job.0.handle)
}

///|
fn OpenJob::fd(job : OpenJob) -> @fd_util.Fd {
  open_job_get_fd_ffi(job.0.handle)
}

///|
fn OpenJob::kind(job : OpenJob) -> @fd_util.FileKind {
  open_job_get_kind_ffi(job.0.handle)
}

///|
fn OpenJob::dev_id(job : OpenJob) -> UInt64 {
  open_job_get_dev_id_ffi(job.0.handle)
}

///|
fn OpenJob::file_id(job : OpenJob) -> UInt64 {
  open_job_get_file_id_ffi(job.0.handle)
}

///|
pub(all) enum Access {
  Exist = 0
  CanRead = 1
  CanWrite = 2
  CanExecute = 3
}

///|
fn unsupported_job() -> Job {
  abort("moonbitlang/async wasm job is not supported in this MVP")
}

///|
fn Job::kind_of_fd(_fd : @fd_util.Fd) -> Job {
  unsupported_job()
}

///|
fn Job::file_kind_by_path(
  _parent : @fd_util.Fd,
  _path : @os_string.OsString,
  follow_symlink~ : Bool,
) -> Job {
  ignore(follow_symlink)
  unsupported_job()
}

///|
fn Job::file_size(_fd : @fd_util.Fd) -> Job {
  unsupported_job()
}

///|
fn Job::get_file_size_result(_job : Job) -> Int64 {
  0
}

///|
fn Job::file_time(_fd : @fd_util.Fd, _out : @fd_util.FileTime) -> Job {
  unsupported_job()
}

///|
fn Job::file_time_by_path(
  _path : @os_string.OsString,
  _out : @fd_util.FileTime,
  follow_symlink~ : Bool,
) -> Job {
  ignore(follow_symlink)
  unsupported_job()
}

///|
fn Job::access(_path : @os_string.OsString, _access : Access) -> Job {
  unsupported_job()
}

///|
fn Job::chmod(_path : @os_string.OsString, _mode : Int) -> Job {
  unsupported_job()
}

///|
fn Job::fsync(_fd : @fd_util.Fd, _only_data : Bool) -> Job {
  unsupported_job()
}

///|
fn Job::flock(_fd : @fd_util.Fd, _exclusive : Bool) -> Job {
  unsupported_job()
}

///|
fn Job::remove(_path : @os_string.OsString) -> Job {
  unsupported_job()
}

///|
fn Job::rename(
  _old_path : @os_string.OsString,
  _new_path : @os_string.OsString,
  replace~ : Bool,
) -> Job {
  ignore(replace)
  unsupported_job()
}

///|
fn Job::symlink(
  _target : @os_string.OsString,
  _path : @os_string.OsString,
) -> Job {
  unsupported_job()
}

///|
fn Job::mkdir(_path : @os_string.OsString, _mode : Int) -> Job {
  unsupported_job()
}

///|
fn Job::rmdir(_path : @os_string.OsString) -> Job {
  unsupported_job()
}

///|
fn Job::readdir(
  _dir : @fd_util.Fd,
  _buf : FixedArray[Byte],
  _len : Int,
  _restart : Bool,
) -> Job {
  unsupported_job()
}

///|
fn Job::realpath(_path : @os_string.OsString) -> Job {
  unsupported_job()
}

///|
fn Job::get_realpath_result(_job : Job) -> @c_buffer.Buffer {
  abort("realpath is not supported for wasm yet")
}

///|
fn Job::wait_for_process(_pid : Int) -> Job {
  unsupported_job()
}

///|
fn Job::bind(_socket : @fd_util.Fd, _addr : Bytes) -> Job {
  unsupported_job()
}

///|
fn Job::getaddrinfo(_host : @os_string.OsString) -> Job {
  unsupported_job()
}

///|
fn Job::get_getaddrinfo_result(_job : Job) -> AddrInfo {
  abort("getaddrinfo is not supported for wasm yet")
}

///|
fn Job::sigwait(_signals : ReadOnlyArray[Int]) -> Job {
  unsupported_job()
}

///|
fn Job::inotify_add_watch(
  _inotify : @fd_util.Fd,
  _path : @os_string.OsString,
  is_dir : Bool,
) -> Job {
  ignore(is_dir)
  unsupported_job()
}

///|
priv struct AddrInfo(Int)
