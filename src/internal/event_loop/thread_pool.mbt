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
#external
priv type NativeJob

///|
extern "C" fn init_thread_pool_ffi(notify_send : @fd_util.Fd) = "moonbitlang_async_init_thread_pool"

///|
extern "C" fn destroy_thread_pool() = "moonbitlang_async_destroy_thread_pool"

///|
extern "C" fn Worker::spawn(init_job_id : Int, init_job : NativeJob) -> Worker = "moonbitlang_async_spawn_worker"

///|
extern "C" fn Worker::free(worker : Worker) = "moonbitlang_async_free_worker"

///|
extern "C" fn Worker::wake(worker : Worker, job_id : Int, job : NativeJob) = "moonbitlang_async_wake_worker"

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
priv struct ThreadPool {
  max_worker_count : Int
  job_queue : @deque.Deque[Job]
  idle_workers : @deque.Deque[Worker]
  running_workers : Map[Int, Worker]
}

///|
priv struct Job {
  id : Int
  native : NativeJob
}

///|
fn ThreadPool::new(max_worker_count~ : Int) -> ThreadPool {
  {
    max_worker_count,
    job_queue: @deque.Deque([]),
    idle_workers: @deque.Deque([]),
    running_workers: {},
  }
}

///|
fn ThreadPool::has_pending_work(self : ThreadPool) -> Bool {
  !self.running_workers.is_empty()
}

///|
fn Job::id(self : Job) -> Int {
  self.id
}

///|
fn Job::free(self : Job) -> Unit {
  self.native.free()
}

///|
fn Job::ret(self : Job) -> Int {
  self.native.ret()
}

///|
fn Job::err(self : Job) -> Int {
  self.native.err()
}

///|
fn ThreadPool::submit_job(
  self : ThreadPool,
  id : Int,
  native : NativeJob,
) -> Job {
  let job = { id, native }
  match self.idle_workers.pop_front() {
    None if self.running_workers.length() >= self.max_worker_count =>
      self.job_queue.push_back(job)
    None => {
      let worker = Worker::spawn(job.id, job.native)
      self.running_workers[job.id] = worker
    }
    Some(worker) => {
      self.running_workers[job.id] = worker
      worker.wake(job.id, job.native)
    }
  }
  job
}

///|
fn ThreadPool::complete(self : ThreadPool, id : Int) -> Bool {
  guard self.running_workers.get(id) is Some(worker) else { false }
  self.running_workers.remove(id)
  match self.job_queue.pop_front() {
    None => {
      worker.enter_idle()
      self.idle_workers.push_back(worker)
    }
    Some(job) => {
      self.running_workers[job.id] = worker
      worker.wake(job.id, job.native)
    }
  }
  true
}

///|
fn ThreadPool::remove_queued_job(self : ThreadPool, id : Int) -> Bool {
  let kept : @deque.Deque[Job] = @deque.Deque([])
  let mut removed = false
  while self.job_queue.pop_front() is Some(job) {
    if job.id == id {
      removed = true
    } else {
      kept.push_back(job)
    }
  }
  while kept.pop_front() is Some(job) {
    self.job_queue.push_back(job)
  }
  removed
}

///|
fn ThreadPool::cancel(
  self : ThreadPool,
  job : Job,
  context~ : String,
) -> CancellationStatus raise {
  if self.running_workers.get(job.id) is Some(worker) {
    worker.cancel(context~)
  } else if self.remove_queued_job(job.id) {
    NoWait
  } else {
    NoWait
  }
}

///|
fn ThreadPool::cleanup(self : ThreadPool) -> Unit {
  for worker in self.idle_workers {
    worker.free()
  }
}

///|
// Keep raw native-job FFI constructors in this file so higher-level
// fs/io/network/process code only builds semantic `OperationSpec`s.
extern "C" fn NativeJob::free(self : NativeJob) -> Unit = "moonbitlang_async_free_job"

///|
extern "C" fn NativeJob::ret(self : NativeJob) -> Int = "moonbitlang_async_job_get_ret"

///|
extern "C" fn NativeJob::err(self : NativeJob) -> Int = "moonbitlang_async_job_get_err"

///|
#owned(buf)
extern "C" fn NativeJob::read(
  fd : @fd_util.Fd,
  buf : FixedArray[Byte],
  offset : Int,
  len : Int,
  // `-1` indicates no offset
  position~ : Int64,
) -> NativeJob = "moonbitlang_async_make_read_job"

///|
#owned(buf)
extern "C" fn NativeJob::write(
  fd : @fd_util.Fd,
  buf : Bytes,
  offset : Int,
  len : Int,
  // `-1` indicates no offset
  position~ : Int64,
) -> NativeJob = "moonbitlang_async_make_write_job"

///|
#owned(filename)
extern "C" fn NativeJob::open(
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
) -> OpenJob = "moonbitlang_async_make_open_job"

///|
priv struct OpenJob(NativeJob)

///|
extern "C" fn OpenJob::fd(job : OpenJob) -> @fd_util.Fd = "moonbitlang_async_open_job_get_fd"

///|
extern "C" fn OpenJob::kind(job : OpenJob) -> @fd_util.FileKind = "moonbitlang_async_open_job_get_kind"

///|
extern "C" fn OpenJob::dev_id(job : OpenJob) -> UInt64 = "moonbitlang_async_open_job_get_dev_id"

///|
extern "C" fn OpenJob::file_id(job : OpenJob) -> UInt64 = "moonbitlang_async_open_job_get_file_id"

///|
extern "C" fn NativeJob::kind_of_fd(fd : @fd_util.Fd) -> NativeJob = "moonbitlang_async_make_kind_of_fd_job"

///|
#owned(path)
extern "C" fn NativeJob::file_kind_by_path(
  parent : @fd_util.Fd,
  path : @os_string.OsString,
  follow_symlink~ : Bool,
) -> NativeJob = "moonbitlang_async_make_file_kind_by_path_job"

///|
extern "C" fn NativeJob::file_size(fd : @fd_util.Fd) -> NativeJob = "moonbitlang_async_make_file_size_job"

///|
extern "C" fn NativeJob::get_file_size_result(job : NativeJob) -> Int64 = "moonbitlang_async_get_file_size_result"

///|
#owned(out)
extern "C" fn NativeJob::file_time(
  fd : @fd_util.Fd,
  out : @fd_util.FileTime,
) -> NativeJob = "moonbitlang_async_make_file_time_job"

///|
#owned(path, out)
extern "C" fn NativeJob::file_time_by_path(
  path : @os_string.OsString,
  out : @fd_util.FileTime,
  follow_symlink~ : Bool,
) -> NativeJob = "moonbitlang_async_make_file_time_by_path_job"

///|
pub(all) enum Access {
  Exist = 0
  CanRead = 1
  CanWrite = 2
  CanExecute = 3
}

///|
#owned(path)
extern "C" fn NativeJob::access(
  path : @os_string.OsString,
  access : Access,
) -> NativeJob = "moonbitlang_async_make_access_job"

///|
#cfg(not(platform="windows"))
#owned(path)
extern "C" fn NativeJob::chmod(
  path : @os_string.OsString,
  mode : Int,
) -> NativeJob = "moonbitlang_async_make_chmod_job"

///|
extern "C" fn NativeJob::fsync(fd : @fd_util.Fd, only_data : Bool) -> NativeJob = "moonbitlang_async_make_fsync_job"

///|
extern "C" fn NativeJob::flock(fd : @fd_util.Fd, exclusive : Bool) -> NativeJob = "moonbitlang_async_make_flock_job"

///|
#owned(path)
extern "C" fn NativeJob::remove(path : @os_string.OsString) -> NativeJob = "moonbitlang_async_make_remove_job"

///|
#owned(old_path, new_path)
extern "C" fn NativeJob::rename(
  old_path : @os_string.OsString,
  new_path : @os_string.OsString,
  replace~ : Bool,
) -> NativeJob = "moonbitlang_async_make_rename_job"

///|
#owned(target, path)
extern "C" fn NativeJob::symlink(
  target : @os_string.OsString,
  path : @os_string.OsString,
  force_symlink~ : Bool,
) -> NativeJob = "moonbitlang_async_make_symlink_job"

///|
#owned(path)
extern "C" fn NativeJob::mkdir(
  path : @os_string.OsString,
  mode : Int,
) -> NativeJob = "moonbitlang_async_make_mkdir_job"

///|
#owned(path)
extern "C" fn NativeJob::rmdir(path : @os_string.OsString) -> NativeJob = "moonbitlang_async_make_rmdir_job"

///|
#owned(buf)
extern "C" fn NativeJob::readdir(
  dir : @fd_util.Fd,
  buf : FixedArray[Byte],
  len : Int,
  restart : Bool,
) -> NativeJob = "moonbitlang_async_make_readdir_job"

///|
#owned(path)
extern "C" fn NativeJob::realpath(path : @os_string.OsString) -> NativeJob = "moonbitlang_async_make_realpath_job"

///|
extern "C" fn NativeJob::get_realpath_result(
  job : NativeJob,
) -> @c_buffer.Buffer = "moonbitlang_async_get_realpath_result"

///|
#cfg(not(platform="windows"))
#owned(path, args, env, cwd)
extern "C" fn NativeJob::spawn(
  path : @os_string.OsString,
  args : FixedArray[@os_string.OsString?],
  env : FixedArray[@os_string.OsString?],
  stdin : @fd_util.Fd,
  stdout : @fd_util.Fd,
  stderr : @fd_util.Fd,
  cwd : @os_string.OsString?,
) -> NativeJob = "moonbitlang_async_make_spawn_job"

///|
#cfg(platform="windows")
#owned(command_line, env, cwd)
extern "C" fn NativeJob::spawn(
  command_line : @os_string.OsString,
  env : @os_string.OsString?,
  stdin : @fd_util.Fd,
  stdout : @fd_util.Fd,
  stderr : @fd_util.Fd,
  cwd : @os_string.OsString?,
  no_console_window~ : Bool,
  is_orphan~ : Bool,
) -> NativeJob = "moonbitlang_async_make_spawn_job"

///|
#cfg(platform="windows")
extern "C" fn NativeJob::get_spawn_job_result_handle(
  job : NativeJob,
) -> @fd_util.Fd = "moonbitlang_async_get_spawn_job_result_handle"

///|
#cfg(not(platform="windows"))
extern "C" fn NativeJob::wait_for_process(pid : Int) -> NativeJob = "moonbitlang_async_make_wait_for_process_job"

///|
#cfg(platform="windows")
extern "C" fn NativeJob::wait_for_process(handle : @fd_util.Fd) -> NativeJob = "moonbitlang_async_make_wait_for_process_job"

///|
#cfg(platform="windows")
extern "C" fn NativeJob::cancel_process_waiter(job : NativeJob) = "moonbitlang_async_cancel_wait_for_process_job"

///|
#owned(addr)
extern "C" fn NativeJob::bind(socket : @fd_util.Fd, addr : Bytes) -> NativeJob = "moonbitlang_async_make_bind_job"

///|
#owned(host)
extern "C" fn NativeJob::getaddrinfo(host : @os_string.OsString) -> NativeJob = "moonbitlang_async_make_getaddrinfo_job"

///|
extern "C" fn NativeJob::get_getaddrinfo_result(job : NativeJob) -> AddrInfo = "moonbitlang_async_get_getaddrinfo_result"

///|
#cfg(not(platform="windows"))
#borrow(signals)
extern "C" fn NativeJob::sigwait(signals : ReadOnlyArray[Int]) -> NativeJob = "moonbitlang_async_make_sigwait_job"

///|
#cfg(not(platform="windows"))
#owned(path)
extern "C" fn NativeJob::inotify_add_watch(
  inotify : @fd_util.Fd,
  path : @os_string.OsString,
  is_dir : Bool,
) -> NativeJob = "moonbitlang_async_make_inotify_add_watch_job"

///|
#cfg(platform="windows")
let _mute_unused_warning : Unit = ignore(@c_buffer.Buffer::get)

///|
fn SubmittedOperation::free(self : SubmittedOperation) -> Unit {
  self.job().free()
}

///|
fn SubmittedOperation::ret(self : SubmittedOperation) -> Int {
  self.job().ret()
}

///|
fn SubmittedOperation::err(self : SubmittedOperation) -> Int {
  self.job().err()
}

///|
priv struct OpenJobResult {
  fd : @fd_util.Fd
  kind : @fd_util.FileKind
  identity : FileIdentity
}

///|
fn SubmittedOperation::open_result(self : SubmittedOperation) -> OpenJobResult {
  let job = OpenJob(self.job().native)
  {
    fd: job.fd(),
    kind: job.kind(),
    identity: { dev_id: job.dev_id(), file_id: job.file_id() },
  }
}

///|
fn SubmittedOperation::file_size_result(self : SubmittedOperation) -> Int64 {
  self.job().native.get_file_size_result()
}

///|
fn SubmittedOperation::realpath_result(
  self : SubmittedOperation,
) -> @c_buffer.Buffer {
  self.job().native.get_realpath_result()
}

///|
#cfg(platform="windows")
fn SubmittedOperation::spawn_result_handle(
  self : SubmittedOperation,
) -> @fd_util.Fd {
  self.job().native.get_spawn_job_result_handle()
}

///|
#cfg(platform="windows")
fn SubmittedOperation::cancel_process_waiter(self : SubmittedOperation) -> Unit {
  self.job().native.cancel_process_waiter()
}

///|
fn SubmittedOperation::getaddrinfo_result(
  self : SubmittedOperation,
) -> AddrInfo {
  self.job().native.get_getaddrinfo_result()
}
