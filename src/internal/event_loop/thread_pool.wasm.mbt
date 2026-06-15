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
fn init_thread_pool_ffi() -> Unit {
  ()
}

///|
fn destroy_thread_pool() -> Unit {
  ()
}

///|
fn spawn_worker_ffi(init_job_id : Int, init_job : Int) -> Int = "moonbit_v0" "thread_pool/spawn_worker"

///|
fn free_worker_ffi(worker : Int) -> Unit = "moonbit_v0" "thread_pool/free_worker"

///|
fn wake_worker_ffi(worker : Int, job_id : Int, job : Int) -> Unit = "moonbit_v0" "thread_pool/wake_worker"

///|
fn worker_enter_idle_ffi(worker : Int) -> Unit = "moonbit_v0" "thread_pool/worker_enter_idle"

///|
fn cancel_worker_ffi(worker : Int) -> Int = "moonbit_v0" "thread_pool/cancel_worker"

///|
fn fetch_completion_raw(output : Int, len : Int) -> Int = "moonbit_v0" "thread_pool/fetch_completion"

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
    // The wasm host cannot interrupt every blocking OS operation yet. It still
    // drains the worker completion later, but cancellation should resume the
    // coroutine immediately to match the async timeout surface.
    0 => NoWait
    1 => NeedWait
    2 => RetryLater
    _ => {
      @os_error.check_errno(context)
      NoWait
    }
  }
}

///|
// Guest state keeps delayed output buffers alive while the opaque host job
// handle is pending. Inputs are copied by moonrun during job construction.
priv enum JobGuestState {
  NoGuestState
  OutputBuffer(FixedArray[Byte])
  FileTimeOutput(@fd_util.FileTime)
}

///|
priv struct Job {
  handle : Int
  state : JobGuestState
}

///|
fn JobGuestState::keep_alive(self : JobGuestState) -> Unit {
  match self {
    NoGuestState => ()
    OutputBuffer(buf) => ignore(buf)
    FileTimeOutput(out) => ignore(out)
  }
}

///|
fn free_job_ffi(job : Int) -> Unit = "moonbit_v0" "thread_pool/free_job"

///|
fn run_job_ffi(job : Int) -> Unit = "moonbit_v0" "thread_pool/run_job"

///|
fn job_get_ret_ffi(job : Int) -> Int = "moonbit_v0" "thread_pool/job_get_ret"

///|
fn job_get_err_ffi(job : Int) -> Int = "moonbit_v0" "thread_pool/job_get_err"

///|
fn make_read_job_ffi(
  fd : @fd_util.Fd,
  buf : Int,
  offset : Int,
  len : Int,
  position : Int64,
) -> Int = "moonbit_v0" "thread_pool/make_read_job"

///|
fn make_write_job_ffi(
  fd : @fd_util.Fd,
  buf : Int,
  offset : Int,
  len : Int,
  position : Int64,
) -> Int = "moonbit_v0" "thread_pool/make_write_job"

// Path job imports pass borrowed MoonBit String pointers. The length is the
// number of UTF-16 code units, not bytes; moonrun converts the string data
// into the host path representation.

///|
fn make_open_job_ffi(
  filename : Int,
  filename_len : Int,
  access : Int,
  create : Int,
  append : Bool,
  sync : Int,
  mode : Int,
) -> Int = "moonbit_v0" "thread_pool/make_open_job"

///|
fn open_job_get_fd_ffi(job : Int) -> @fd_util.Fd = "moonbit_v0" "thread_pool/open_job_get_fd"

///|
fn open_job_get_kind_ffi(job : Int) -> @fd_util.FileKind = "moonbit_v0" "thread_pool/open_job_get_kind"

///|
fn open_job_get_dev_id_ffi(job : Int) -> UInt64 = "moonbit_v0" "thread_pool/open_job_get_dev_id"

///|
fn open_job_get_file_id_ffi(job : Int) -> UInt64 = "moonbit_v0" "thread_pool/open_job_get_file_id"

///|
fn make_file_kind_by_path_job_ffi(
  parent : @fd_util.Fd,
  path : Int,
  path_len : Int,
  follow_symlink : Bool,
) -> Int = "moonbit_v0" "thread_pool/make_file_kind_by_path_job"

///|
fn make_file_size_job_ffi(fd : @fd_util.Fd) -> Int = "moonbit_v0" "thread_pool/make_file_size_job"

///|
fn get_file_size_result_ffi(job : Int) -> Int64 = "moonbit_v0" "thread_pool/get_file_size_result"

///|
fn make_file_time_job_ffi(fd : @fd_util.Fd, out : Int, len : Int) -> Int = "moonbit_v0" "thread_pool/make_file_time_job"

///|
fn make_file_time_by_path_job_ffi(
  path : Int,
  path_len : Int,
  out : Int,
  len : Int,
  follow_symlink : Bool,
) -> Int = "moonbit_v0" "thread_pool/make_file_time_by_path_job"

///|
fn make_access_job_ffi(path : Int, path_len : Int, access : Int) -> Int = "moonbit_v0" "thread_pool/make_access_job"

///|
fn make_chmod_job_ffi(path : Int, path_len : Int, mode : Int) -> Int = "moonbit_v0" "thread_pool/make_chmod_job"

///|
fn make_fsync_job_ffi(fd : @fd_util.Fd, only_data : Bool) -> Int = "moonbit_v0" "thread_pool/make_fsync_job"

///|
fn make_flock_job_ffi(fd : @fd_util.Fd, exclusive : Bool) -> Int = "moonbit_v0" "thread_pool/make_flock_job"

///|
fn make_remove_job_ffi(path : Int, path_len : Int) -> Int = "moonbit_v0" "thread_pool/make_remove_job"

///|
fn make_rename_job_ffi(
  old_path : Int,
  old_path_len : Int,
  new_path : Int,
  new_path_len : Int,
  replace : Bool,
) -> Int = "moonbit_v0" "thread_pool/make_rename_job"

///|
fn make_symlink_job_ffi(
  target : Int,
  target_len : Int,
  path : Int,
  path_len : Int,
  force_symlink : Bool,
) -> Int = "moonbit_v0" "thread_pool/make_symlink_job"

///|
fn make_mkdir_job_ffi(path : Int, path_len : Int, mode : Int) -> Int = "moonbit_v0" "thread_pool/make_mkdir_job"

///|
fn make_rmdir_job_ffi(path : Int, path_len : Int) -> Int = "moonbit_v0" "thread_pool/make_rmdir_job"

///|
fn make_readdir_job_ffi(
  dir : @fd_util.Fd,
  buf : Int,
  len : Int,
  restart : Bool,
) -> Int = "moonbit_v0" "thread_pool/make_readdir_job"

///|
fn make_wait_for_process_job_ffi(process : Int) -> Int = "moonbit_v0" "thread_pool/make_wait_for_process_job"

///|
fn Job::free(self : Job) -> Unit {
  free_job_ffi(self.handle)
}

///|
fn Job::run(self : Job) -> Unit {
  run_job_ffi(self.handle)
}

///|
fn Job::ret(self : Job) -> Int {
  self.state.keep_alive()
  job_get_ret_ffi(self.handle)
}

///|
fn Job::err(self : Job) -> Int {
  self.state.keep_alive()
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
    state: OutputBuffer(buf),
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
    state: NoGuestState,
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
  let filename_string = filename.to_string()
  let job = {
    handle: make_open_job_ffi(
      @wasm_ffi.string_to_ptr(filename_string),
      filename_string.length(),
      access,
      create,
      append,
      sync,
      mode,
    ),
    state: NoGuestState,
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
fn Access::to_int(self : Access) -> Int = "%identity"

///|
fn Job::file_kind_by_path(
  parent : @fd_util.Fd,
  path : @os_string.OsString,
  follow_symlink~ : Bool,
) -> Job {
  let path_string = path.to_string()
  {
    handle: make_file_kind_by_path_job_ffi(
      parent,
      @wasm_ffi.string_to_ptr(path_string),
      path_string.length(),
      follow_symlink,
    ),
    state: NoGuestState,
  }
}

///|
fn Job::file_size(fd : @fd_util.Fd) -> Job {
  {
    handle: make_file_size_job_ffi(fd),
    state: NoGuestState,
  }
}

///|
fn Job::get_file_size_result(job : Job) -> Int64 {
  get_file_size_result_ffi(job.handle)
}

///|
fn Job::file_time(fd : @fd_util.Fd, out : @fd_util.FileTime) -> Job {
  {
    handle: make_file_time_job_ffi(fd, out.ptr(), out.length()),
    state: FileTimeOutput(out),
  }
}

///|
fn Job::file_time_by_path(
  path : @os_string.OsString,
  out : @fd_util.FileTime,
  follow_symlink~ : Bool,
) -> Job {
  let path_string = path.to_string()
  {
    handle: make_file_time_by_path_job_ffi(
      @wasm_ffi.string_to_ptr(path_string),
      path_string.length(),
      out.ptr(),
      out.length(),
      follow_symlink,
    ),
    state: FileTimeOutput(out),
  }
}

///|
fn Job::access(path : @os_string.OsString, access : Access) -> Job {
  let path_string = path.to_string()
  {
    handle: make_access_job_ffi(
      @wasm_ffi.string_to_ptr(path_string),
      path_string.length(),
      access.to_int(),
    ),
    state: NoGuestState,
  }
}

///|
fn Job::chmod(path : @os_string.OsString, mode : Int) -> Job {
  let path_string = path.to_string()
  {
    handle: make_chmod_job_ffi(
      @wasm_ffi.string_to_ptr(path_string),
      path_string.length(),
      mode,
    ),
    state: NoGuestState,
  }
}

///|
fn Job::fsync(fd : @fd_util.Fd, only_data : Bool) -> Job {
  {
    handle: make_fsync_job_ffi(fd, only_data),
    state: NoGuestState,
  }
}

///|
fn Job::flock(fd : @fd_util.Fd, exclusive : Bool) -> Job {
  {
    handle: make_flock_job_ffi(fd, exclusive),
    state: NoGuestState,
  }
}

///|
fn Job::remove(path : @os_string.OsString) -> Job {
  let path_string = path.to_string()
  {
    handle: make_remove_job_ffi(
      @wasm_ffi.string_to_ptr(path_string),
      path_string.length(),
    ),
    state: NoGuestState,
  }
}

///|
fn Job::rename(
  old_path : @os_string.OsString,
  new_path : @os_string.OsString,
  replace~ : Bool,
) -> Job {
  let old_path_string = old_path.to_string()
  let new_path_string = new_path.to_string()
  {
    handle: make_rename_job_ffi(
      @wasm_ffi.string_to_ptr(old_path_string),
      old_path_string.length(),
      @wasm_ffi.string_to_ptr(new_path_string),
      new_path_string.length(),
      replace,
    ),
    state: NoGuestState,
  }
}

///|
fn Job::symlink(
  target : @os_string.OsString,
  path : @os_string.OsString,
  force_symlink~ : Bool,
) -> Job {
  let target_string = target.to_string()
  let path_string = path.to_string()
  {
    handle: make_symlink_job_ffi(
      @wasm_ffi.string_to_ptr(target_string),
      target_string.length(),
      @wasm_ffi.string_to_ptr(path_string),
      path_string.length(),
      force_symlink,
    ),
    state: NoGuestState,
  }
}

///|
fn Job::mkdir(path : @os_string.OsString, mode : Int) -> Job {
  let path_string = path.to_string()
  {
    handle: make_mkdir_job_ffi(
      @wasm_ffi.string_to_ptr(path_string),
      path_string.length(),
      mode,
    ),
    state: NoGuestState,
  }
}

///|
fn Job::rmdir(path : @os_string.OsString) -> Job {
  let path_string = path.to_string()
  {
    handle: make_rmdir_job_ffi(
      @wasm_ffi.string_to_ptr(path_string),
      path_string.length(),
    ),
    state: NoGuestState,
  }
}

///|
fn Job::readdir(
  dir : @fd_util.Fd,
  buf : FixedArray[Byte],
  len : Int,
  restart : Bool,
) -> Job {
  {
    handle: make_readdir_job_ffi(
      dir,
      @wasm_ffi.byte_array_to_ptr(buf),
      len,
      restart,
    ),
    state: OutputBuffer(buf),
  }
}

///|
fn Job::wait_for_process(process : Int) -> Job {
  {
    handle: make_wait_for_process_job_ffi(process),
    state: NoGuestState,
  }
}
