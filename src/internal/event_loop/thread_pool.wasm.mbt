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
fn Worker::spawn_ffi(init_job_id : Int, init_job : JobHandle) -> Worker = "moonbitlang/async" "thread_pool/spawn_worker"

///|
fn Worker::spawn(init_job_id : Int, init_job : Job) -> Worker {
  Worker::spawn_ffi(init_job_id, init_job.handle)
}

///|
#unsafe_skip_stub_check
fn Worker::free(worker : Worker) -> Unit = "moonbitlang/async" "thread_pool/free_worker"

///|
#unsafe_skip_stub_check
fn Worker::wake_ffi(worker : Worker, job_id : Int, job : JobHandle) -> Unit = "moonbitlang/async" "thread_pool/wake_worker"

///|
fn Worker::wake(worker : Worker, job_id : Int, job : Job) -> Unit {
  worker.wake_ffi(job_id, job.handle)
}

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
/// The actual job object submitted to the thread pool in runtime
priv struct JobHandle(UInt64)

///|
/// In WASM backend, letting the thread pool occupy reference to
/// (mapped) physical address of WASM memory is unsafe,
/// because `memory.grow` may change the base address of WASM memory.
/// Hence for all output buffer passed to the thread pool,
/// we need to allocate a temporary buffer in the runtime instead,
/// and copy output data to the MoonBit buffer only after job completion.
/// To align with native API, this copy phase is implemented as a callback.
#valtype
priv struct Job {
  handle : JobHandle
  copy_output : ((JobHandle) -> Unit)?
}

///|
fn Job::Job(handle : JobHandle, copy_output? : (JobHandle) -> Unit) -> Job {
  { handle, copy_output }
}

///|
#unsafe_skip_stub_check
fn JobHandle::free(self : JobHandle) -> Unit = "moonbitlang/async" "thread_pool/free_job"

///|
fn Job::free(self : Job) -> Unit {
  self.handle.free()
}

///|
#unsafe_skip_stub_check
fn JobHandle::ret(self : JobHandle) -> Int = "moonbitlang/async" "thread_pool/job_get_ret"

///|
fn Job::ret(self : Job) -> Int {
  self.handle.ret()
}

///|
#unsafe_skip_stub_check
fn JobHandle::err(self : JobHandle) -> Int = "moonbitlang/async" "thread_pool/job_get_err"

///|
fn Job::err(self : Job) -> Int {
  self.handle.err()
}

///|
fn Job::copy_output(self : Job) -> Unit {
  if self.copy_output is Some(copy_output) {
    copy_output(self.handle)
  }
}

///|
#unsafe_skip_stub_check
fn JobHandle::read(fd : @fd_util.Fd, len : Int, position~ : Int64) -> JobHandle = "moonbitlang/async" "thread_pool/make_read_job"

///|
#unsafe_skip_stub_check
#borrow(buf)
fn JobHandle::get_read_result(
  self : JobHandle,
  buf : FixedArray[Byte],
  offset : Int,
  len : Int,
) -> Unit = "moonbitlang/async" "thread_pool/get_read_result"

///|
fn Job::read(
  fd : @fd_util.Fd,
  buf : FixedArray[Byte],
  offset : Int,
  len : Int,
  // `-1` indicates no offset
  position~ : Int64,
) -> Job {
  Job(JobHandle::read(fd, len, position~), copy_output=job => {
    job.get_read_result(buf, offset, len)
  })
}

///|
#unsafe_skip_stub_check
#borrow(buf)
fn JobHandle::write(
  fd : @fd_util.Fd,
  buf : Bytes,
  offset : Int,
  len : Int,
  // `-1` indicates no offset
  position~ : Int64,
) -> JobHandle = "moonbitlang/async" "thread_pool/make_write_job"

///|
fn Job::write(
  fd : @fd_util.Fd,
  buf : Bytes,
  offset : Int,
  len : Int,
  // `-1` indicates no offset
  position~ : Int64,
) -> Job {
  Job(JobHandle::write(fd, buf, offset, len, position~))
}

///|
#unsafe_skip_stub_check
#borrow(filename)
fn JobHandle::open(
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
) -> JobHandle = "moonbitlang/async" "thread_pool/make_open_job"

///|
priv struct OpenJob(Job)

///|
fn Job::open(
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
) -> OpenJob {
  Job(JobHandle::open(filename, access, create~, append~, sync~, mode~))
}

///|
#unsafe_skip_stub_check
fn OpenJob::fd_ffi(job : JobHandle) -> @fd_util.Fd = "moonbitlang/async" "thread_pool/open_job_get_fd"

///|
fn OpenJob::fd(job : OpenJob) -> @fd_util.Fd {
  OpenJob::fd_ffi(job.0.handle)
}

///|
#unsafe_skip_stub_check
fn OpenJob::kind_ffi(job : JobHandle) -> @fd_util.FileKind = "moonbitlang/async" "thread_pool/open_job_get_kind"

///|
fn OpenJob::kind(job : OpenJob) -> @fd_util.FileKind {
  OpenJob::kind_ffi(job.0.handle)
}

///|
#unsafe_skip_stub_check
fn OpenJob::dev_id_ffi(job : JobHandle) -> UInt64 = "moonbitlang/async" "thread_pool/open_job_get_dev_id"

///|
fn OpenJob::dev_id(job : OpenJob) -> UInt64 {
  OpenJob::dev_id_ffi(job.0.handle)
}

///|
#unsafe_skip_stub_check
fn OpenJob::file_id_ffi(job : JobHandle) -> UInt64 = "moonbitlang/async" "thread_pool/open_job_get_file_id"

///|
fn OpenJob::file_id(job : OpenJob) -> UInt64 {
  OpenJob::file_id_ffi(job.0.handle)
}

///|
#unsafe_skip_stub_check
#borrow(path)
fn JobHandle::file_kind_by_path(
  parent : @fd_util.Fd,
  path : @os_string.OsString,
  path_len? : Int = path.to_string().length(),
  follow_symlink~ : Bool,
) -> JobHandle = "moonbitlang/async" "thread_pool/make_file_kind_by_path_job"

///|
fn Job::file_kind_by_path(
  parent : @fd_util.Fd,
  path : @os_string.OsString,
  follow_symlink~ : Bool,
) -> Job {
  Job(JobHandle::file_kind_by_path(parent, path, follow_symlink~))
}

///|
#unsafe_skip_stub_check
fn JobHandle::file_size(fd : @fd_util.Fd) -> JobHandle = "moonbitlang/async" "thread_pool/make_file_size_job"

///|
fn Job::file_size(fd : @fd_util.Fd) -> Job {
  Job(JobHandle::file_size(fd))
}

///|
#unsafe_skip_stub_check
fn JobHandle::get_file_size_result(job : JobHandle) -> Int64 = "moonbitlang/async" "thread_pool/get_file_size_result"

///|
fn Job::get_file_size_result(job : Job) -> Int64 {
  job.handle.get_file_size_result()
}

///|
#unsafe_skip_stub_check
fn JobHandle::file_time(fd : @fd_util.Fd) -> JobHandle = "moonbitlang/async" "thread_pool/make_file_time_job"

///|
fn Job::file_time(fd : @fd_util.Fd, out : @fd_util.FileTime) -> Job {
  Job(JobHandle::file_time(fd), copy_output=job => job.get_file_time_result(out))
}

///|
#unsafe_skip_stub_check
#borrow(path)
fn JobHandle::file_time_by_path(
  path : @os_string.OsString,
  path_len? : Int = path.to_string().length(),
  follow_symlink~ : Bool,
) -> JobHandle = "moonbitlang/async" "thread_pool/make_file_time_by_path_job"

///|
fn Job::file_time_by_path(
  path : @os_string.OsString,
  out : @fd_util.FileTime,
  follow_symlink~ : Bool,
) -> Job {
  Job(JobHandle::file_time_by_path(path, follow_symlink~), copy_output=job => {
    job.get_file_time_result(out)
  })
}

///|
#unsafe_skip_stub_check
#borrow(out)
fn JobHandle::get_file_time_result(
  self : JobHandle,
  out : @fd_util.FileTime,
) -> Unit = "moonbitlang/async" "thread_pool/get_file_time_result"

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
fn JobHandle::access(
  path : @os_string.OsString,
  path_len? : Int = path.to_string().length(),
  access : Access,
) -> JobHandle = "moonbitlang/async" "thread_pool/make_access_job"

///|
fn Job::access(path : @os_string.OsString, access : Access) -> Job {
  Job(JobHandle::access(path, access))
}

///|
#unsafe_skip_stub_check
#borrow(path)
fn JobHandle::chmod(
  path : @os_string.OsString,
  path_len? : Int = path.to_string().length(),
  mode : Int,
) -> JobHandle = "moonbitlang/async" "thread_pool/make_chmod_job"

///|
fn Job::chmod(path : @os_string.OsString, mode : Int) -> Job {
  Job(JobHandle::chmod(path, mode))
}

///|
#unsafe_skip_stub_check
fn JobHandle::fsync(fd : @fd_util.Fd, only_data : Bool) -> JobHandle = "moonbitlang/async" "thread_pool/make_fsync_job"

///|
fn Job::fsync(fd : @fd_util.Fd, only_data : Bool) -> Job {
  Job(JobHandle::fsync(fd, only_data))
}

///|
#unsafe_skip_stub_check
fn JobHandle::flock(fd : @fd_util.Fd, exclusive : Bool) -> JobHandle = "moonbitlang/async" "thread_pool/make_flock_job"

///|
fn Job::flock(fd : @fd_util.Fd, exclusive : Bool) -> Job {
  Job(JobHandle::flock(fd, exclusive))
}

///|
#unsafe_skip_stub_check
#borrow(path)
fn JobHandle::remove(
  path : @os_string.OsString,
  path_len? : Int = path.to_string().length(),
) -> JobHandle = "moonbitlang/async" "thread_pool/make_remove_job"

///|
fn Job::remove(path : @os_string.OsString) -> Job {
  Job(JobHandle::remove(path))
}

///|
#unsafe_skip_stub_check
#borrow(old_path, new_path)
fn JobHandle::rename(
  old_path : @os_string.OsString,
  old_path_len? : Int = old_path.to_string().length(),
  new_path : @os_string.OsString,
  new_path_len? : Int = new_path.to_string().length(),
  replace~ : Bool,
) -> JobHandle = "moonbitlang/async" "thread_pool/make_rename_job"

///|
fn Job::rename(
  old_path : @os_string.OsString,
  new_path : @os_string.OsString,
  replace~ : Bool,
) -> Job {
  Job(JobHandle::rename(old_path, new_path, replace~))
}

///|
#unsafe_skip_stub_check
#borrow(target, path)
fn JobHandle::symlink(
  target : @os_string.OsString,
  target_len? : Int = target.to_string().length(),
  path : @os_string.OsString,
  path_len? : Int = path.to_string().length(),
  force_symlink~ : Bool,
) -> JobHandle = "moonbitlang/async" "thread_pool/make_symlink_job"

///|
fn Job::symlink(
  target : @os_string.OsString,
  path : @os_string.OsString,
  force_symlink~ : Bool,
) -> Job {
  Job(JobHandle::symlink(target, path, force_symlink~))
}

///|
#unsafe_skip_stub_check
#borrow(path)
fn JobHandle::mkdir(
  path : @os_string.OsString,
  path_len? : Int = path.to_string().length(),
  mode : Int,
) -> JobHandle = "moonbitlang/async" "thread_pool/make_mkdir_job"

///|
fn Job::mkdir(path : @os_string.OsString, mode : Int) -> Job {
  Job(JobHandle::mkdir(path, mode))
}

///|
#unsafe_skip_stub_check
#borrow(path)
fn JobHandle::rmdir(
  path : @os_string.OsString,
  path_len? : Int = path.to_string().length(),
) -> JobHandle = "moonbitlang/async" "thread_pool/make_rmdir_job"

///|
fn Job::rmdir(path : @os_string.OsString) -> Job {
  Job(JobHandle::rmdir(path))
}

///|
#unsafe_skip_stub_check
#borrow(buf)
fn JobHandle::readdir(
  dir : @fd_util.Fd,
  buf : @c_buffer.Buffer,
  len : Int,
  restart : Bool,
) -> JobHandle = "moonbitlang/async" "thread_pool/make_readdir_job"

///|
fn Job::readdir(
  dir : @fd_util.Fd,
  buf : @c_buffer.Buffer,
  len : Int,
  restart : Bool,
) -> Job {
  Job(JobHandle::readdir(dir, buf, len, restart))
}

///|
#unsafe_skip_stub_check
#borrow(addr)
fn JobHandle::bind(
  socket : @fd_util.Fd,
  addr : Bytes,
  addr_len? : Int = addr.length(),
) -> JobHandle = "moonbitlang/async" "thread_pool/make_bind_job"

///|
fn Job::bind(socket : @fd_util.Fd, addr : Bytes) -> Job {
  Job(JobHandle::bind(socket, addr))
}

///|
#unsafe_skip_stub_check
#borrow(host)
fn JobHandle::getaddrinfo(
  host : @os_string.OsString,
  host_len? : Int = host.to_string().length(),
) -> JobHandle = "moonbitlang/async" "thread_pool/make_getaddrinfo_job"

///|
fn Job::getaddrinfo(host : @os_string.OsString) -> Job {
  Job(JobHandle::getaddrinfo(host))
}

///|
#unsafe_skip_stub_check
fn JobHandle::get_getaddrinfo_result(job : JobHandle) -> AddrInfo = "moonbitlang/async" "thread_pool/get_getaddrinfo_result"

///|
fn Job::get_getaddrinfo_result(job : Job) -> AddrInfo {
  job.handle.get_getaddrinfo_result()
}

///|
#unsafe_skip_stub_check
#borrow(path)
fn JobHandle::realpath(
  path : @os_string.OsString,
  path_len? : Int = path.to_string().length(),
) -> JobHandle = "moonbitlang/async" "thread_pool/make_realpath_job"

///|
fn Job::realpath(path : @os_string.OsString) -> Job {
  Job(JobHandle::realpath(path))
}

///|
#unsafe_skip_stub_check
fn JobHandle::get_realpath_result(job : JobHandle) -> @c_buffer.Buffer = "moonbitlang/async" "thread_pool/get_realpath_result"

///|
fn Job::get_realpath_result(job : Job) -> @c_buffer.Buffer {
  job.handle.get_realpath_result()
}

///|
priv struct SpawnJob(Job)

///|
#unsafe_skip_stub_check
#borrow(path, cwd)
fn JobHandle::spawn_unix(
  path : @os_string.OsString,
  path_len? : Int = path.to_string().length(),
  args : UInt64,
  env~ : UInt64,
  inherited_env_entry_count~ : Int,
  stdin~ : @fd_util.Fd,
  stdout~ : @fd_util.Fd,
  stderr~ : @fd_util.Fd,
  cwd~ : @os_string.OsString,
  cwd_len? : Int = cwd.to_string().length(),
  has_cwd~ : Bool,
) -> JobHandle = "moonbitlang/async" "thread_pool/make_spawn_job/unix"

///|
fn Job::spawn_unix(
  path : @os_string.OsString,
  args : UInt64,
  env~ : UInt64,
  inherited_env_entry_count~ : Int,
  stdin~ : @fd_util.Fd,
  stdout~ : @fd_util.Fd,
  stderr~ : @fd_util.Fd,
  cwd~ : @os_string.OsString,
  has_cwd~ : Bool,
) -> SpawnJob {
  SpawnJob(
    Job(
      JobHandle::spawn_unix(
        path,
        args,
        env~,
        inherited_env_entry_count~,
        stdin~,
        stdout~,
        stderr~,
        cwd~,
        has_cwd~,
      ),
    ),
  )
}

///|
#unsafe_skip_stub_check
#borrow(command_line, cwd)
fn JobHandle::spawn_windows(
  command_line : @os_string.OsString,
  command_line_len? : Int = command_line.to_string().length(),
  env~ : UInt64,
  stdin~ : @fd_util.Fd,
  stdout~ : @fd_util.Fd,
  stderr~ : @fd_util.Fd,
  cwd~ : @os_string.OsString,
  cwd_len? : Int = cwd.to_string().length(),
  has_cwd~ : Bool,
  no_console_window~ : Bool,
  is_orphan~ : Bool,
) -> JobHandle = "moonbitlang/async" "thread_pool/make_spawn_job/windows"

///|
fn Job::spawn_windows(
  command_line : @os_string.OsString,
  env~ : UInt64,
  stdin~ : @fd_util.Fd,
  stdout~ : @fd_util.Fd,
  stderr~ : @fd_util.Fd,
  cwd~ : @os_string.OsString,
  has_cwd~ : Bool,
  no_console_window~ : Bool,
  is_orphan~ : Bool,
) -> SpawnJob {
  SpawnJob(
    Job(
      JobHandle::spawn_windows(
        command_line,
        env~,
        stdin~,
        stdout~,
        stderr~,
        cwd~,
        has_cwd~,
        no_console_window~,
        is_orphan~,
      ),
    ),
  )
}

///|
#unsafe_skip_stub_check
#borrow(job)
fn SpawnJob::result_handle(job : SpawnJob) -> @fd_util.Fd = "moonbitlang/async" "thread_pool/get_spawn_job_result_handle"

///|
#unsafe_skip_stub_check
fn JobHandle::wait_for_process(handle : @fd_util.Fd, pid~ : Int) -> JobHandle = "moonbitlang/async" "thread_pool/make_wait_for_process_job"

///|
fn Job::wait_for_process(handle : @fd_util.Fd, pid~ : Int) -> Job {
  Job(JobHandle::wait_for_process(handle, pid~))
}

///|
#unsafe_skip_stub_check
#borrow(signals)
fn JobHandle::sigwait(
  signals : ReadOnlyArray[Int],
  signals_len : Int,
) -> JobHandle = "moonbitlang/async" "thread_pool/make_sigwait_job"

///|
fn Job::sigwait(signals : ReadOnlyArray[Int]) -> Job {
  Job(JobHandle::sigwait(signals, signals.length()))
}
