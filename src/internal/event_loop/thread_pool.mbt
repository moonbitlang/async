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
extern "C" fn init_thread_pool_ffi(notify_send : @fd_util.Fd) = "moonbitlang_async_init_thread_pool"

///|
extern "C" fn destroy_thread_pool() = "moonbitlang_async_destroy_thread_pool"

///|
#borrow(init_job)
extern "C" fn Worker::spawn_ffi(
  init_job_id : Int,
  init_job : FixedArray[Byte],
) -> Worker = "moonbitlang_async_spawn_worker"

///|
fn Worker::spawn(init_job_id : Int, init_job : Job) -> Worker {
  Worker::spawn_ffi(init_job_id, init_job.storage)
}

///|
extern "C" fn Worker::free(worker : Worker) = "moonbitlang_async_free_worker"

///|
#borrow(job)
extern "C" fn Worker::wake_ffi(
  worker : Worker,
  job_id : Int,
  job : FixedArray[Byte],
) = "moonbitlang_async_wake_worker"

///|
fn Worker::wake(worker : Worker, job_id : Int, job : Job) -> Unit {
  worker.wake_ffi(job_id, job.storage)
}

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
#warnings("-unused_mut")
priv struct Job {
  storage : FixedArray[Byte]
  mut bytes : Bytes?
  mut fixed_bytes : FixedArray[Byte]?
  mut path1 : @os_string.OsString?
  mut path2 : @os_string.OsString?
  mut path3 : @os_string.OsString?
  mut path_array1 : FixedArray[@os_string.OsString?]?
  mut path_array2 : FixedArray[@os_string.OsString?]?
  mut file_time : @fd_util.FileTime?
  mut signals : ReadOnlyArray[Int]?
  mut string_result : String?
}

///|
extern "C" fn job_storage_size() -> Int = "moonbitlang_async_job_storage_size"

///|
fn Job::new() -> Job {
  {
    storage: FixedArray::make(job_storage_size(), b'\x00'),
    bytes: None,
    fixed_bytes: None,
    path1: None,
    path2: None,
    path3: None,
    path_array1: None,
    path_array2: None,
    file_time: None,
    signals: None,
    string_result: None,
  }
}

///|
#borrow(storage)
extern "C" fn job_ret_ffi(
  storage : FixedArray[Byte],
) -> Int = "moonbitlang_async_job_get_ret"

///|
fn Job::ret(self : Job) -> Int {
  job_ret_ffi(self.storage)
}

///|
#borrow(storage)
extern "C" fn job_err_ffi(
  storage : FixedArray[Byte],
) -> Int = "moonbitlang_async_job_get_err"

///|
fn Job::err(self : Job) -> Int {
  job_err_ffi(self.storage)
}

///|
#borrow(storage)
extern "C" fn job_cleanup_ffi(
  storage : FixedArray[Byte],
) = "moonbitlang_async_job_cleanup"

///|
fn Job::cleanup(self : Job) -> Unit {
  job_cleanup_ffi(self.storage)
}

///|
fn Job::keepalive(self : Job) -> Unit {
  ignore(self.bytes)
  ignore(self.fixed_bytes)
  ignore(self.path1)
  ignore(self.path2)
  ignore(self.path3)
  ignore(self.path_array1)
  ignore(self.path_array2)
  ignore(self.file_time)
  ignore(self.signals)
  ignore(self.string_result)
}

///|
#cfg(target="native")
#warnings("-unused_value")
fn Job::sleep(time : Int) -> Job {
  let job = Job::new()
  init_sleep_job(job.storage, time)
  job
}

///|
#cfg(target="native")
#borrow(job)
extern "C" fn init_sleep_job(
  job : FixedArray[Byte],
  time : Int,
) = "moonbitlang_async_make_sleep_job"

///|
fn Job::read(
  fd : @fd_util.Fd,
  buf : FixedArray[Byte],
  offset : Int,
  len : Int,
  // `-1` indicates no offset
  position~ : Int64,
) -> Job {
  let job = Job::new()
  job.fixed_bytes = Some(buf)
  init_read_job(job.storage, fd, buf, offset, len, position~)
  job
}

///|
#borrow(job, buf)
extern "C" fn init_read_job(
  job : FixedArray[Byte],
  fd : @fd_util.Fd,
  buf : FixedArray[Byte],
  offset : Int,
  len : Int,
  position~ : Int64,
) = "moonbitlang_async_make_read_job"

///|
fn Job::write(
  fd : @fd_util.Fd,
  buf : Bytes,
  offset : Int,
  len : Int,
  // `-1` indicates no offset
  position~ : Int64,
) -> Job {
  let job = Job::new()
  job.bytes = Some(buf)
  init_write_job(job.storage, fd, buf, offset, len, position~)
  job
}

///|
#borrow(job, buf)
extern "C" fn init_write_job(
  job : FixedArray[Byte],
  fd : @fd_util.Fd,
  buf : Bytes,
  offset : Int,
  len : Int,
  position~ : Int64,
) = "moonbitlang_async_make_write_job"

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
) -> OpenResult {
  let job = Job::new()
  job.path1 = Some(filename)
  init_open_job(job.storage, filename, access, create~, append~, sync~, mode~)
  OpenResult(job)
}

///|
#borrow(job, filename)
extern "C" fn init_open_job(
  job : FixedArray[Byte],
  filename : @os_string.OsString,
  access : Int,
  create~ : Int,
  append~ : Bool,
  sync~ : Int,
  mode~ : Int,
) = "moonbitlang_async_make_open_job"

///|
struct OpenResult(Job)

///|
#borrow(job)
extern "C" fn open_result_fd_ffi(job : FixedArray[Byte]) -> @fd_util.Fd = "moonbitlang_async_open_job_get_fd"

///|
pub fn OpenResult::fd(job : OpenResult) -> @fd_util.Fd {
  open_result_fd_ffi(job.0.storage)
}

///|
#borrow(job)
extern "C" fn open_result_kind_ffi(job : FixedArray[Byte]) -> @fd_util.FileKind = "moonbitlang_async_open_job_get_kind"

///|
pub fn OpenResult::kind(job : OpenResult) -> @fd_util.FileKind {
  open_result_kind_ffi(job.0.storage)
}

///|
fn Job::kind_of_fd(fd : @fd_util.Fd) -> Job {
  let job = Job::new()
  init_kind_of_fd_job(job.storage, fd)
  job
}

///|
#borrow(job)
extern "C" fn init_kind_of_fd_job(
  job : FixedArray[Byte],
  fd : @fd_util.Fd,
) = "moonbitlang_async_make_kind_of_fd_job"

///|
fn Job::file_kind_by_path(
  parent : @fd_util.Fd,
  path : @os_string.OsString,
  follow_symlink~ : Bool,
) -> Job {
  let job = Job::new()
  job.path1 = Some(path)
  init_file_kind_by_path_job(job.storage, parent, path, follow_symlink~)
  job
}

///|
#borrow(job, path)
extern "C" fn init_file_kind_by_path_job(
  job : FixedArray[Byte],
  parent : @fd_util.Fd,
  path : @os_string.OsString,
  follow_symlink~ : Bool,
) = "moonbitlang_async_make_file_kind_by_path_job"

///|
fn Job::file_size(fd : @fd_util.Fd) -> Job {
  let job = Job::new()
  init_file_size_job(job.storage, fd)
  job
}

///|
#borrow(job)
extern "C" fn init_file_size_job(
  job : FixedArray[Byte],
  fd : @fd_util.Fd,
) = "moonbitlang_async_make_file_size_job"

///|
#borrow(job)
extern "C" fn get_file_size_result_ffi(job : FixedArray[Byte]) -> Int64 = "moonbitlang_async_get_file_size_result"

///|
fn Job::get_file_size_result(job : Job) -> Int64 {
  get_file_size_result_ffi(job.storage)
}

///|
fn Job::file_time(fd : @fd_util.Fd, out : @fd_util.FileTime) -> Job {
  let job = Job::new()
  job.file_time = Some(out)
  init_file_time_job(job.storage, fd, out)
  job
}

///|
#borrow(job, out)
extern "C" fn init_file_time_job(
  job : FixedArray[Byte],
  fd : @fd_util.Fd,
  out : @fd_util.FileTime,
) = "moonbitlang_async_make_file_time_job"

///|
fn Job::file_time_by_path(
  path : @os_string.OsString,
  out : @fd_util.FileTime,
  follow_symlink~ : Bool,
) -> Job {
  let job = Job::new()
  job.path1 = Some(path)
  job.file_time = Some(out)
  init_file_time_by_path_job(job.storage, path, out, follow_symlink~)
  job
}

///|
#borrow(job, path, out)
extern "C" fn init_file_time_by_path_job(
  job : FixedArray[Byte],
  path : @os_string.OsString,
  out : @fd_util.FileTime,
  follow_symlink~ : Bool,
) = "moonbitlang_async_make_file_time_by_path_job"

///|
pub(all) enum Access {
  Exist = 0
  CanRead = 1
  CanWrite = 2
  CanExecute = 3
}

///|
fn Job::access(path : @os_string.OsString, access : Access) -> Job {
  let job = Job::new()
  job.path1 = Some(path)
  init_access_job(job.storage, path, access)
  job
}

///|
#borrow(job, path)
extern "C" fn init_access_job(
  job : FixedArray[Byte],
  path : @os_string.OsString,
  access : Access,
) = "moonbitlang_async_make_access_job"

///|
fn Job::chmod(path : @os_string.OsString, mode : Int) -> Job {
  let job = Job::new()
  job.path1 = Some(path)
  init_chmod_job(job.storage, path, mode)
  job
}

///|
#borrow(job, path)
extern "C" fn init_chmod_job(
  job : FixedArray[Byte],
  path : @os_string.OsString,
  mode : Int,
) = "moonbitlang_async_make_chmod_job"

///|
fn Job::fsync(fd : @fd_util.Fd, only_data : Bool) -> Job {
  let job = Job::new()
  init_fsync_job(job.storage, fd, only_data)
  job
}

///|
#borrow(job)
extern "C" fn init_fsync_job(
  job : FixedArray[Byte],
  fd : @fd_util.Fd,
  only_data : Bool,
) = "moonbitlang_async_make_fsync_job"

///|
fn Job::flock(fd : @fd_util.Fd, exclusive : Bool) -> Job {
  let job = Job::new()
  init_flock_job(job.storage, fd, exclusive)
  job
}

///|
#borrow(job)
extern "C" fn init_flock_job(
  job : FixedArray[Byte],
  fd : @fd_util.Fd,
  exclusive : Bool,
) = "moonbitlang_async_make_flock_job"

///|
fn Job::remove(path : @os_string.OsString) -> Job {
  let job = Job::new()
  job.path1 = Some(path)
  init_remove_job(job.storage, path)
  job
}

///|
#borrow(job, path)
extern "C" fn init_remove_job(
  job : FixedArray[Byte],
  path : @os_string.OsString,
) = "moonbitlang_async_make_remove_job"

///|
fn Job::rename(
  old_path : @os_string.OsString,
  new_path : @os_string.OsString,
  replace~ : Bool,
) -> Job {
  let job = Job::new()
  job.path1 = Some(old_path)
  job.path2 = Some(new_path)
  init_rename_job(job.storage, old_path, new_path, replace~)
  job
}

///|
#borrow(job, old_path, new_path)
extern "C" fn init_rename_job(
  job : FixedArray[Byte],
  old_path : @os_string.OsString,
  new_path : @os_string.OsString,
  replace~ : Bool,
) = "moonbitlang_async_make_rename_job"

///|
fn Job::symlink(
  target : @os_string.OsString,
  path : @os_string.OsString,
) -> Job {
  let job = Job::new()
  job.path1 = Some(target)
  job.path2 = Some(path)
  init_symlink_job(job.storage, target, path)
  job
}

///|
#borrow(job, target, path)
extern "C" fn init_symlink_job(
  job : FixedArray[Byte],
  target : @os_string.OsString,
  path : @os_string.OsString,
) = "moonbitlang_async_make_symlink_job"

///|
fn Job::mkdir(path : @os_string.OsString, mode : Int) -> Job {
  let job = Job::new()
  job.path1 = Some(path)
  init_mkdir_job(job.storage, path, mode)
  job
}

///|
#borrow(job, path)
extern "C" fn init_mkdir_job(
  job : FixedArray[Byte],
  path : @os_string.OsString,
  mode : Int,
) = "moonbitlang_async_make_mkdir_job"

///|
fn Job::rmdir(path : @os_string.OsString) -> Job {
  let job = Job::new()
  job.path1 = Some(path)
  init_rmdir_job(job.storage, path)
  job
}

///|
#borrow(job, path)
extern "C" fn init_rmdir_job(
  job : FixedArray[Byte],
  path : @os_string.OsString,
) = "moonbitlang_async_make_rmdir_job"

///|
fn Job::readdir(
  dir : @fd_util.Fd,
  buf : FixedArray[Byte],
  len : Int,
) -> Job {
  let job = Job::new()
  job.fixed_bytes = Some(buf)
  init_readdir_job(job.storage, dir, buf, len)
  job
}

///|
#borrow(job, buf)
extern "C" fn init_readdir_job(
  job : FixedArray[Byte],
  dir : @fd_util.Fd,
  buf : FixedArray[Byte],
  len : Int,
) = "moonbitlang_async_make_readdir_job"

///|
#cfg(not(platform="windows"))
fn Job::realpath(path : @os_string.OsString) -> Job {
  let job = Job::new()
  job.path1 = Some(path)
  init_realpath_job(job.storage, path)
  job
}

///|
#cfg(not(platform="windows"))
#borrow(job, path)
extern "C" fn init_realpath_job(
  job : FixedArray[Byte],
  path : @os_string.OsString,
) = "moonbitlang_async_make_realpath_job"

///|
#cfg(platform="windows")
fn Job::realpath(path : @os_string.OsString) -> Job {
  let job = Job::new()
  let result = String::make(32768, '\u{0}')
  job.path1 = Some(path)
  job.string_result = Some(result)
  init_realpath_job(job.storage, path, result, result.length())
  job
}

///|
#cfg(platform="windows")
#borrow(job, path, result)
extern "C" fn init_realpath_job(
  job : FixedArray[Byte],
  path : @os_string.OsString,
  result : String,
  result_len : Int,
) = "moonbitlang_async_make_realpath_job"

///|
#cfg(not(platform="windows"))
#borrow(job)
extern "C" fn get_realpath_result_ffi(
  job : FixedArray[Byte],
) -> @c_buffer.Buffer = "moonbitlang_async_get_realpath_result"

///|
#cfg(not(platform="windows"))
fn Job::get_realpath_result(job : Job) -> @c_buffer.Buffer {
  get_realpath_result_ffi(job.storage)
}

///|
#cfg(platform="windows")
fn Job::get_realpath_result(job : Job) -> String {
  match job.string_result {
    Some(result) => result[:job.ret()].to_owned()
    None => abort("missing realpath output buffer")
  }
}

///|
#cfg(not(platform="windows"))
fn Job::spawn(
  path : @os_string.OsString,
  args : FixedArray[@os_string.OsString?],
  env : FixedArray[@os_string.OsString?],
  stdin : @fd_util.Fd,
  stdout : @fd_util.Fd,
  stderr : @fd_util.Fd,
  cwd : @os_string.OsString?,
) -> Job {
  let job = Job::new()
  job.path1 = Some(path)
  job.path2 = cwd
  job.path_array1 = Some(args)
  job.path_array2 = Some(env)
  init_spawn_job(job.storage, path, args, env, stdin, stdout, stderr, cwd)
  job
}

///|
#cfg(not(platform="windows"))
#borrow(job, path, args, env, cwd)
extern "C" fn init_spawn_job(
  job : FixedArray[Byte],
  path : @os_string.OsString,
  args : FixedArray[@os_string.OsString?],
  env : FixedArray[@os_string.OsString?],
  stdin : @fd_util.Fd,
  stdout : @fd_util.Fd,
  stderr : @fd_util.Fd,
  cwd : @os_string.OsString?,
) = "moonbitlang_async_make_spawn_job"

///|
#cfg(platform="windows")
fn Job::spawn(
  command_line : @os_string.OsString,
  env : @os_string.OsString?,
  stdin : @fd_util.Fd,
  stdout : @fd_util.Fd,
  stderr : @fd_util.Fd,
  cwd : @os_string.OsString?,
  is_orphan~ : Bool,
) -> Job {
  let job = Job::new()
  job.path1 = Some(command_line)
  job.path2 = env
  job.path3 = cwd
  init_spawn_job(
    job.storage,
    command_line,
    env,
    stdin,
    stdout,
    stderr,
    cwd,
    is_orphan~,
  )
  job
}

///|
#cfg(platform="windows")
#borrow(job, command_line, env, cwd)
extern "C" fn init_spawn_job(
  job : FixedArray[Byte],
  command_line : @os_string.OsString,
  env : @os_string.OsString?,
  stdin : @fd_util.Fd,
  stdout : @fd_util.Fd,
  stderr : @fd_util.Fd,
  cwd : @os_string.OsString?,
  is_orphan~ : Bool,
) = "moonbitlang_async_make_spawn_job"

///|
#cfg(platform="windows")
#borrow(job)
extern "C" fn get_spawn_job_result_handle_ffi(
  job : FixedArray[Byte],
) -> @fd_util.Fd = "moonbitlang_async_get_spawn_job_result_handle"

///|
#cfg(platform="windows")
fn Job::get_spawn_job_result_handle(job : Job) -> @fd_util.Fd {
  get_spawn_job_result_handle_ffi(job.storage)
}

///|
#cfg(not(platform="windows"))
fn Job::wait_for_process(pid : Int) -> Job {
  let job = Job::new()
  init_wait_for_process_job(job.storage, pid)
  job
}

///|
#cfg(not(platform="windows"))
#borrow(job)
extern "C" fn init_wait_for_process_job(
  job : FixedArray[Byte],
  pid : Int,
) = "moonbitlang_async_make_wait_for_process_job"

///|
#cfg(platform="windows")
fn Job::wait_for_process(handle : @fd_util.Fd) -> Job {
  let job = Job::new()
  init_wait_for_process_job(job.storage, handle)
  job
}

///|
#cfg(platform="windows")
#borrow(job)
extern "C" fn init_wait_for_process_job(
  job : FixedArray[Byte],
  handle : @fd_util.Fd,
) = "moonbitlang_async_make_wait_for_process_job"

///|
#cfg(platform="windows")
#borrow(job)
extern "C" fn cancel_process_waiter_ffi(
  job : FixedArray[Byte],
) = "moonbitlang_async_cancel_wait_for_process_job"

///|
#cfg(platform="windows")
fn Job::cancel_process_waiter(job : Job) -> Unit {
  cancel_process_waiter_ffi(job.storage)
}

///|
fn Job::bind(socket : @fd_util.Fd, addr : Bytes) -> Job {
  let job = Job::new()
  job.bytes = Some(addr)
  init_bind_job(job.storage, socket, addr)
  job
}

///|
#borrow(job, addr)
extern "C" fn init_bind_job(
  job : FixedArray[Byte],
  socket : @fd_util.Fd,
  addr : Bytes,
) = "moonbitlang_async_make_bind_job"

///|
fn Job::getaddrinfo(host : @os_string.OsString) -> Job {
  let job = Job::new()
  job.path1 = Some(host)
  init_getaddrinfo_job(job.storage, host)
  job
}

///|
#borrow(job, host)
extern "C" fn init_getaddrinfo_job(
  job : FixedArray[Byte],
  host : @os_string.OsString,
) = "moonbitlang_async_make_getaddrinfo_job"

///|
#borrow(job)
extern "C" fn get_getaddrinfo_result_ffi(
  job : FixedArray[Byte],
) -> AddrInfo = "moonbitlang_async_get_getaddrinfo_result"

///|
fn Job::get_getaddrinfo_result(job : Job) -> AddrInfo {
  get_getaddrinfo_result_ffi(job.storage)
}

///|
#cfg(not(platform="windows"))
fn Job::sigwait(signals : ReadOnlyArray[Int]) -> Job {
  let job = Job::new()
  job.signals = Some(signals)
  init_sigwait_job(job.storage, signals)
  job
}

///|
#cfg(not(platform="windows"))
#borrow(job, signals)
extern "C" fn init_sigwait_job(
  job : FixedArray[Byte],
  signals : ReadOnlyArray[Int],
) = "moonbitlang_async_make_sigwait_job"

///|
#cfg(platform="windows")
let _mute_unused_warning : Unit = ignore(@c_buffer.Buffer::get)
