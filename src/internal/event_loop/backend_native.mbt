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
// Native operation requests describe what async operation is needed, not how it
// is implemented. The backend lowers these cases to readiness waits, IOCP
// completions, or thread-pool jobs.
//
// The common variants live here because both native adapters can lower them.
// Unix-only and Windows-only variants extend the same `extenum` under `#cfg`
// below, so the call sites keep one operation language while target-specific
// lowering remains local to the native backend.
priv extenum OperationSpec += {
  TimerOp(Int64)
  ReadOp(@fd_util.Fd, FixedArray[Byte], Int, Int, Int64)
  WriteOp(@fd_util.Fd, Bytes, Int, Int, Int64)
  OpenOp(@os_string.OsString, Int, Int, Bool, Int, Int)
  KindOfFdOp(@fd_util.Fd)
  FileKindByPathOp(@fd_util.Fd, @os_string.OsString, Bool)
  FileSizeOp(@fd_util.Fd)
  FileTimeOp(@fd_util.Fd, @fd_util.FileTime)
  FileTimeByPathOp(@os_string.OsString, @fd_util.FileTime, Bool)
  AccessOp(@os_string.OsString, Access)
  FsyncOp(@fd_util.Fd, Bool)
  FlockOp(@fd_util.Fd, Bool)
  RemoveOp(@os_string.OsString)
  RenameOp(@os_string.OsString, @os_string.OsString, Bool)
  SymlinkOp(@os_string.OsString, @os_string.OsString, Bool)
  MkdirOp(@os_string.OsString, Int)
  RmdirOp(@os_string.OsString)
  ReaddirOp(@fd_util.Fd, FixedArray[Byte], Int, Bool)
  RealpathOp(@os_string.OsString)
  BindOp(@fd_util.Fd, Bytes)
  GetAddrInfoOp(@os_string.OsString)
}

///|
#cfg(not(platform="windows"))
priv extenum OperationSpec += {
  FdReadOp(@fd_util.Fd)
  FdWriteOp(@fd_util.Fd)
  ProcessWaitOp(Int)
  SpawnUnixOp(
    @os_string.OsString,
    FixedArray[@os_string.OsString?],
    FixedArray[@os_string.OsString?],
    @fd_util.Fd,
    @fd_util.Fd,
    @fd_util.Fd,
    @os_string.OsString?
  )
  ChmodOp(@os_string.OsString, Int)
  WaitForProcessOp(Int)
  SigwaitOp(ReadOnlyArray[Int])
  InotifyAddWatchOp(@fd_util.Fd, @os_string.OsString, Bool)
}

///|
#cfg(platform="windows")
priv extenum OperationSpec += {
  SpawnWindowsOp(
    @os_string.OsString,
    @os_string.OsString?,
    @fd_util.Fd,
    @fd_util.Fd,
    @fd_util.Fd,
    @os_string.OsString?,
    Bool,
    Bool
  )
  WaitForProcessOp(@fd_util.Fd)
}

///|
fn OperationSpec::timer(deadline : Int64) -> OperationSpec {
  TimerOp(deadline)
}

///|
#cfg(not(platform="windows"))
fn OperationSpec::fd_read(fd : @fd_util.Fd) -> OperationSpec {
  FdReadOp(fd)
}

///|
#cfg(not(platform="windows"))
fn OperationSpec::fd_write(fd : @fd_util.Fd) -> OperationSpec {
  FdWriteOp(fd)
}

///|
#cfg(not(platform="windows"))
fn OperationSpec::process_wait(pid_handle : Int) -> OperationSpec {
  ProcessWaitOp(pid_handle)
}

///|
fn OperationSpec::read(
  fd : @fd_util.Fd,
  buf : FixedArray[Byte],
  offset : Int,
  len : Int,
  position~ : Int64,
) -> OperationSpec {
  ReadOp(fd, buf, offset, len, position)
}

///|
fn OperationSpec::write(
  fd : @fd_util.Fd,
  buf : Bytes,
  offset : Int,
  len : Int,
  position~ : Int64,
) -> OperationSpec {
  WriteOp(fd, buf, offset, len, position)
}

///|
fn OperationSpec::open(
  filename : @os_string.OsString,
  access : Int,
  create~ : Int,
  append~ : Bool,
  sync~ : Int,
  mode~ : Int,
) -> OperationSpec {
  OpenOp(filename, access, create, append, sync, mode)
}

///|
fn OperationSpec::kind_of_fd(fd : @fd_util.Fd) -> OperationSpec {
  KindOfFdOp(fd)
}

///|
fn OperationSpec::file_kind_by_path(
  parent : @fd_util.Fd,
  path : @os_string.OsString,
  follow_symlink~ : Bool,
) -> OperationSpec {
  FileKindByPathOp(parent, path, follow_symlink)
}

///|
fn OperationSpec::file_size(fd : @fd_util.Fd) -> OperationSpec {
  FileSizeOp(fd)
}

///|
fn OperationSpec::file_time(
  fd : @fd_util.Fd,
  out : @fd_util.FileTime,
) -> OperationSpec {
  FileTimeOp(fd, out)
}

///|
fn OperationSpec::file_time_by_path(
  path : @os_string.OsString,
  out : @fd_util.FileTime,
  follow_symlink~ : Bool,
) -> OperationSpec {
  FileTimeByPathOp(path, out, follow_symlink)
}

///|
fn OperationSpec::access(
  path : @os_string.OsString,
  access : Access,
) -> OperationSpec {
  AccessOp(path, access)
}

///|
#cfg(not(platform="windows"))
fn OperationSpec::chmod(
  path : @os_string.OsString,
  mode : Int,
) -> OperationSpec {
  ChmodOp(path, mode)
}

///|
fn OperationSpec::fsync(fd : @fd_util.Fd, only_data : Bool) -> OperationSpec {
  FsyncOp(fd, only_data)
}

///|
fn OperationSpec::flock(fd : @fd_util.Fd, exclusive : Bool) -> OperationSpec {
  FlockOp(fd, exclusive)
}

///|
fn OperationSpec::remove(path : @os_string.OsString) -> OperationSpec {
  RemoveOp(path)
}

///|
fn OperationSpec::rename(
  old_path : @os_string.OsString,
  new_path : @os_string.OsString,
  replace~ : Bool,
) -> OperationSpec {
  RenameOp(old_path, new_path, replace)
}

///|
fn OperationSpec::symlink(
  target : @os_string.OsString,
  path : @os_string.OsString,
  force_symlink~ : Bool,
) -> OperationSpec {
  SymlinkOp(target, path, force_symlink)
}

///|
fn OperationSpec::mkdir(
  path : @os_string.OsString,
  mode : Int,
) -> OperationSpec {
  MkdirOp(path, mode)
}

///|
fn OperationSpec::rmdir(path : @os_string.OsString) -> OperationSpec {
  RmdirOp(path)
}

///|
fn OperationSpec::readdir(
  dir : @fd_util.Fd,
  buf : FixedArray[Byte],
  len : Int,
  restart : Bool,
) -> OperationSpec {
  ReaddirOp(dir, buf, len, restart)
}

///|
fn OperationSpec::realpath(path : @os_string.OsString) -> OperationSpec {
  RealpathOp(path)
}

///|
#cfg(not(platform="windows"))
fn OperationSpec::spawn(
  path : @os_string.OsString,
  args : FixedArray[@os_string.OsString?],
  env : FixedArray[@os_string.OsString?],
  stdin : @fd_util.Fd,
  stdout : @fd_util.Fd,
  stderr : @fd_util.Fd,
  cwd : @os_string.OsString?,
) -> OperationSpec {
  SpawnUnixOp(path, args, env, stdin, stdout, stderr, cwd)
}

///|
#cfg(platform="windows")
fn OperationSpec::spawn(
  command_line : @os_string.OsString,
  env : @os_string.OsString?,
  stdin : @fd_util.Fd,
  stdout : @fd_util.Fd,
  stderr : @fd_util.Fd,
  cwd : @os_string.OsString?,
  no_console_window~ : Bool,
  is_orphan~ : Bool,
) -> OperationSpec {
  SpawnWindowsOp(
    command_line, env, stdin, stdout, stderr, cwd, no_console_window, is_orphan,
  )
}

///|
#cfg(not(platform="windows"))
fn OperationSpec::wait_for_process(pid : Int) -> OperationSpec {
  WaitForProcessOp(pid)
}

///|
#cfg(platform="windows")
fn OperationSpec::wait_for_process(handle : @fd_util.Fd) -> OperationSpec {
  WaitForProcessOp(handle)
}

///|
fn OperationSpec::bind(socket : @fd_util.Fd, addr : Bytes) -> OperationSpec {
  BindOp(socket, addr)
}

///|
fn OperationSpec::getaddrinfo(host : @os_string.OsString) -> OperationSpec {
  GetAddrInfoOp(host)
}

///|
#cfg(not(platform="windows"))
fn OperationSpec::sigwait(signals : ReadOnlyArray[Int]) -> OperationSpec {
  SigwaitOp(signals)
}

///|
#cfg(not(platform="windows"))
fn OperationSpec::inotify_add_watch(
  inotify : @fd_util.Fd,
  path : @os_string.OsString,
  is_dir : Bool,
) -> OperationSpec {
  InotifyAddWatchOp(inotify, path, is_dir)
}

///|
#cfg(not(platform="windows"))
async fn wait_operation(spec : OperationSpec) -> Unit {
  guard curr_loop.val is Some(evloop)
  let (subscription_id, _) = evloop.subscribe_operation(
    spec,
    Wake(@coroutine.current_coroutine()),
  )
  defer evloop.unsubscribe(subscription_id)
  @coroutine.suspend()
}

///|
#warnings("-unused_constructor")
priv extenum SubmittedOperation += {
  NativeTimerOperation(Int)
  NativeFdReadOperation(@fd_util.Fd)
  NativeFdWriteOperation(@fd_util.Fd)
  NativeProcessWaitOperation(Int)
  NativeCompletionOperation(Int)
  NativeThreadPoolOperation(Job)
}

///|
fn SubmittedOperation::job(self : SubmittedOperation) -> Job {
  match self {
    NativeThreadPoolOperation(job) => job
    _ => abort("operation has no native thread-pool job")
  }
}

///|
priv struct EventLoopHook {
  init : (() -> Unit raise)?
  exit : (() -> Unit raise)?
}

///|
let hooks : Array[EventLoopHook] = []

///|
pub fn register_hook(
  init? : () -> Unit raise,
  exit? : () -> Unit raise,
) -> Unit {
  hooks.push({ init, exit })
}

///|
pub let check_fd_leak : Ref[Bool] = Ref(
  @env.get_env_var("MOONBIT_ASYNC_CHECK_FD_LEAK") is Some(_),
)

///|
fn EventLoop::has_subscription(self : EventLoop, subscription_id : Int) -> Bool {
  self.subscriptions.get(subscription_id) is Some(_)
}

///|
fn Backend::spawn_main(
  backend : Backend,
  evloop : EventLoop,
  f : async () -> Unit,
) -> @coroutine.Coroutine raise {
  for hook in hooks {
    if hook.init is Some(init) {
      init()
    }
  }
  let signal_handler = setup_signal_handler()
  let main = @coroutine.spawn(() => {
    try f() catch {
      err => {
        evloop.terminate_signal_handler(signal_handler)
        raise err
      }
    } noraise {
      _ => evloop.terminate_signal_handler(signal_handler)
    }
  })
  backend.main = Some(main)
  main
}

///|
fn Backend::operation_cancelled(
  backend : Backend,
  operation : SubmittedOperation,
) -> Unit {
  match operation {
    NativeTimerOperation(subscription_id) =>
      backend.timer_waiters.remove(subscription_id)
    NativeFdReadOperation(fd) => backend.read_waiters.remove(fd)
    NativeFdWriteOperation(fd) => backend.write_waiters.remove(fd)
    NativeProcessWaitOperation(pid_handle) =>
      backend.process_waiters.remove(pid_handle)
    NativeCompletionOperation(operation_id) =>
      backend.completion_waiters.remove(operation_id)
    NativeThreadPoolOperation(job) =>
      backend.completion_waiters.remove(job.id())
    _ => ()
  }
}

///|
fn Backend::has_pending_work(backend : Backend) -> Bool {
  backend.thread_pool.has_pending_work()
}

///|
fn Backend::next_operation_id(backend : Backend) -> Int {
  let operation_id = backend.operation_id
  backend.operation_id += 1
  operation_id
}

///|
fn Backend::next_timer_timeout(
  backend : Backend,
  _evloop : EventLoop,
  blocking~ : Bool,
) -> Int {
  guard blocking else { 0 }
  let mut now = 0L
  let mut has_now = false
  let mut timeout = -1
  for _, deadline in backend.timer_waiters {
    if !has_now {
      now = @time.ms_since_epoch()
      has_now = true
    }
    let remaining = @cmp.maximum(0, (deadline - now).to_int())
    if timeout == -1 || remaining < timeout {
      timeout = remaining
    }
  }
  timeout
}

///|
fn Backend::ready_timers(backend : Backend, _evloop : EventLoop) -> Array[Int] {
  let ready : Array[(Int64, Int)] = []
  let mut now = 0L
  let mut has_now = false
  for subscription_id, deadline in backend.timer_waiters {
    if !has_now {
      now = @time.ms_since_epoch()
      has_now = true
    }
    if deadline <= now {
      ready.push((deadline, subscription_id))
    }
  }
  ready.sort()
  let subscription_ids : Array[Int] = []
  for item in ready {
    let (_, subscription_id) = item
    subscription_ids.push(subscription_id)
  }
  subscription_ids
}

///|
fn Backend::ready_thread_pool_completion(
  backend : Backend,
  job_id : Int,
) -> Int? {
  if (job_id & (1 << 31)) != 0 {
    if backend.main is Some(main) {
      main.cancel()
    }
    backend.killed_by_signal = Some(job_id ^ (1 << 31))
    None
  } else {
    guard backend.thread_pool.complete(job_id) else { None }
    backend.completion_waiters.get(job_id)
  }
}

///|
#cfg(platform="windows")
fn Backend::completion_operation(
  backend : Backend,
  subscription_id : Int,
  operation_id : Int,
) -> SubmittedOperation {
  backend.completion_waiters[operation_id] = subscription_id
  NativeCompletionOperation(operation_id)
}

///|
fn Backend::check_fd_leak(backend : Backend) -> Unit {
  if check_fd_leak.val && !backend.fds.is_empty() {
    let leaked_handles = [
      for handle in backend.fds.values() => @debug.to_string(handle.kind)
    ].join(", ")
    abort("file descriptor leak detected: \{leaked_handles}")
  }
}

///|
fn EventLoop::cleanup_after_error(self : EventLoop) -> Unit {
  self.backend.cleanup(self) catch {
    _ => ()
  }
  self.cleanup_subscriptions()
}

///|
fn EventLoop::cleanup_after_success(self : EventLoop) -> Unit raise {
  defer self.cleanup_subscriptions()
  self.backend.cleanup(self)
}

///|
fn Backend::submit_thread_pool_job(
  backend : Backend,
  subscription_id : Int,
  native : NativeJob,
) -> SubmittedOperation {
  let job = backend.thread_pool.submit_job(backend.next_operation_id(), native)
  backend.completion_waiters[job.id()] = subscription_id
  NativeThreadPoolOperation(job)
}

///|
#cfg(not(platform="windows"))
fn Backend::submit_operation(
  backend : Backend,
  subscription_id : Int,
  spec : OperationSpec,
) -> SubmittedOperation {
  match spec {
    TimerOp(deadline) => {
      backend.timer_waiters[subscription_id] = deadline
      NativeTimerOperation(subscription_id)
    }
    FdReadOp(fd) => {
      backend.read_waiters[fd] = subscription_id
      NativeFdReadOperation(fd)
    }
    FdWriteOp(fd) => {
      backend.write_waiters[fd] = subscription_id
      NativeFdWriteOperation(fd)
    }
    ProcessWaitOp(pid_handle) => {
      backend.process_waiters[pid_handle] = subscription_id
      NativeProcessWaitOperation(pid_handle)
    }
    ReadOp(fd, buf, offset, len, position) =>
      backend.submit_thread_pool_job(
        subscription_id,
        NativeJob::read(fd, buf, offset, len, position~),
      )
    WriteOp(fd, buf, offset, len, position) =>
      backend.submit_thread_pool_job(
        subscription_id,
        NativeJob::write(fd, buf, offset, len, position~),
      )
    OpenOp(filename, access, create, append, sync, mode) => {
      let job = NativeJob::open(
        filename,
        access,
        create~,
        append~,
        sync~,
        mode~,
      )
      backend.submit_thread_pool_job(subscription_id, job.0)
    }
    KindOfFdOp(fd) =>
      backend.submit_thread_pool_job(subscription_id, NativeJob::kind_of_fd(fd))
    FileKindByPathOp(parent, path, follow_symlink) =>
      backend.submit_thread_pool_job(
        subscription_id,
        NativeJob::file_kind_by_path(parent, path, follow_symlink~),
      )
    FileSizeOp(fd) =>
      backend.submit_thread_pool_job(subscription_id, NativeJob::file_size(fd))
    FileTimeOp(fd, out) =>
      backend.submit_thread_pool_job(
        subscription_id,
        NativeJob::file_time(fd, out),
      )
    FileTimeByPathOp(path, out, follow_symlink) =>
      backend.submit_thread_pool_job(
        subscription_id,
        NativeJob::file_time_by_path(path, out, follow_symlink~),
      )
    AccessOp(path, access) =>
      backend.submit_thread_pool_job(
        subscription_id,
        NativeJob::access(path, access),
      )
    FsyncOp(fd, only_data) =>
      backend.submit_thread_pool_job(
        subscription_id,
        NativeJob::fsync(fd, only_data),
      )
    FlockOp(fd, exclusive) =>
      backend.submit_thread_pool_job(
        subscription_id,
        NativeJob::flock(fd, exclusive),
      )
    RemoveOp(path) =>
      backend.submit_thread_pool_job(subscription_id, NativeJob::remove(path))
    RenameOp(old_path, new_path, replace) =>
      backend.submit_thread_pool_job(
        subscription_id,
        NativeJob::rename(old_path, new_path, replace~),
      )
    SymlinkOp(target, path, force_symlink) =>
      backend.submit_thread_pool_job(
        subscription_id,
        NativeJob::symlink(target, path, force_symlink~),
      )
    MkdirOp(path, mode) =>
      backend.submit_thread_pool_job(
        subscription_id,
        NativeJob::mkdir(path, mode),
      )
    RmdirOp(path) =>
      backend.submit_thread_pool_job(subscription_id, NativeJob::rmdir(path))
    ReaddirOp(dir, buf, len, restart) =>
      backend.submit_thread_pool_job(
        subscription_id,
        NativeJob::readdir(dir, buf, len, restart),
      )
    RealpathOp(path) =>
      backend.submit_thread_pool_job(subscription_id, NativeJob::realpath(path))
    WaitForProcessOp(process) =>
      backend.submit_thread_pool_job(
        subscription_id,
        NativeJob::wait_for_process(process),
      )
    BindOp(socket, addr) =>
      backend.submit_thread_pool_job(
        subscription_id,
        NativeJob::bind(socket, addr),
      )
    GetAddrInfoOp(host) =>
      backend.submit_thread_pool_job(
        subscription_id,
        NativeJob::getaddrinfo(host),
      )
    ChmodOp(path, mode) =>
      backend.submit_thread_pool_job(
        subscription_id,
        NativeJob::chmod(path, mode),
      )
    SpawnUnixOp(path, args, env, stdin, stdout, stderr, cwd) =>
      backend.submit_thread_pool_job(
        subscription_id,
        NativeJob::spawn(path, args, env, stdin, stdout, stderr, cwd),
      )
    SigwaitOp(signals) =>
      backend.submit_thread_pool_job(
        subscription_id,
        NativeJob::sigwait(signals),
      )
    InotifyAddWatchOp(inotify, path, is_dir) =>
      backend.submit_thread_pool_job(
        subscription_id,
        NativeJob::inotify_add_watch(inotify, path, is_dir),
      )
    _ => abort("operation is not implemented by the native backend")
  }
}

///|
#cfg(platform="windows")
fn Backend::submit_operation(
  backend : Backend,
  subscription_id : Int,
  spec : OperationSpec,
) -> SubmittedOperation {
  match spec {
    TimerOp(deadline) => {
      backend.timer_waiters[subscription_id] = deadline
      NativeTimerOperation(subscription_id)
    }
    ReadOp(fd, buf, offset, len, position) =>
      backend.submit_thread_pool_job(
        subscription_id,
        NativeJob::read(fd, buf, offset, len, position~),
      )
    WriteOp(fd, buf, offset, len, position) =>
      backend.submit_thread_pool_job(
        subscription_id,
        NativeJob::write(fd, buf, offset, len, position~),
      )
    OpenOp(filename, access, create, append, sync, mode) => {
      let job = NativeJob::open(
        filename,
        access,
        create~,
        append~,
        sync~,
        mode~,
      )
      backend.submit_thread_pool_job(subscription_id, job.0)
    }
    KindOfFdOp(fd) =>
      backend.submit_thread_pool_job(subscription_id, NativeJob::kind_of_fd(fd))
    FileKindByPathOp(parent, path, follow_symlink) =>
      backend.submit_thread_pool_job(
        subscription_id,
        NativeJob::file_kind_by_path(parent, path, follow_symlink~),
      )
    FileSizeOp(fd) =>
      backend.submit_thread_pool_job(subscription_id, NativeJob::file_size(fd))
    FileTimeOp(fd, out) =>
      backend.submit_thread_pool_job(
        subscription_id,
        NativeJob::file_time(fd, out),
      )
    FileTimeByPathOp(path, out, follow_symlink) =>
      backend.submit_thread_pool_job(
        subscription_id,
        NativeJob::file_time_by_path(path, out, follow_symlink~),
      )
    AccessOp(path, access) =>
      backend.submit_thread_pool_job(
        subscription_id,
        NativeJob::access(path, access),
      )
    FsyncOp(fd, only_data) =>
      backend.submit_thread_pool_job(
        subscription_id,
        NativeJob::fsync(fd, only_data),
      )
    FlockOp(fd, exclusive) =>
      backend.submit_thread_pool_job(
        subscription_id,
        NativeJob::flock(fd, exclusive),
      )
    RemoveOp(path) =>
      backend.submit_thread_pool_job(subscription_id, NativeJob::remove(path))
    RenameOp(old_path, new_path, replace) =>
      backend.submit_thread_pool_job(
        subscription_id,
        NativeJob::rename(old_path, new_path, replace~),
      )
    SymlinkOp(target, path, force_symlink) =>
      backend.submit_thread_pool_job(
        subscription_id,
        NativeJob::symlink(target, path, force_symlink~),
      )
    MkdirOp(path, mode) =>
      backend.submit_thread_pool_job(
        subscription_id,
        NativeJob::mkdir(path, mode),
      )
    RmdirOp(path) =>
      backend.submit_thread_pool_job(subscription_id, NativeJob::rmdir(path))
    ReaddirOp(dir, buf, len, restart) =>
      backend.submit_thread_pool_job(
        subscription_id,
        NativeJob::readdir(dir, buf, len, restart),
      )
    RealpathOp(path) =>
      backend.submit_thread_pool_job(subscription_id, NativeJob::realpath(path))
    WaitForProcessOp(process) =>
      backend.submit_thread_pool_job(
        subscription_id,
        NativeJob::wait_for_process(process),
      )
    BindOp(socket, addr) =>
      backend.submit_thread_pool_job(
        subscription_id,
        NativeJob::bind(socket, addr),
      )
    GetAddrInfoOp(host) =>
      backend.submit_thread_pool_job(
        subscription_id,
        NativeJob::getaddrinfo(host),
      )
    SpawnWindowsOp(
      command_line,
      env,
      stdin,
      stdout,
      stderr,
      cwd,
      no_console_window,
      is_orphan
    ) =>
      backend.submit_thread_pool_job(
        subscription_id,
        NativeJob::spawn(
          command_line,
          env,
          stdin,
          stdout,
          stderr,
          cwd,
          no_console_window~,
          is_orphan~,
        ),
      )
    _ => abort("operation is not implemented by the native backend")
  }
}

///|
priv enum CancellationStatus {
  NoWait
  NeedWait
  RetryLater
}

///|
async fn EventLoop::wait_for_submitted_operation(
  evloop : EventLoop,
  subscription_id : Int,
  operation : SubmittedOperation,
  cancel? : (SubmittedOperation) -> CancellationStatus raise,
) -> Unit {
  defer evloop.unsubscribe(subscription_id)
  match cancel {
    None =>
      @coroutine.protect_from_cancel(@coroutine.suspend, resume_on_cancel=true)
    Some(cancel_func) =>
      @coroutine.suspend() catch {
        err =>
          for ;; {
            let status = cancel_func(operation) catch {
              err =>
                @coroutine.protect_from_cancel() <| () => {
                  @coroutine.suspend()
                  raise err
                }
            }
            match status {
              NeedWait => {
                @coroutine.protect_from_cancel(
                  @coroutine.suspend,
                  resume_on_cancel=true,
                )
                break
              }
              NoWait => raise err
              RetryLater => {
                @coroutine.protect_from_cancel(
                  @coroutine.pause,
                  resume_on_cancel=true,
                )
                if !evloop.has_subscription(subscription_id) {
                  break
                }
              }
            }
          }
      }
  }
}

///|
extern "C" fn errno_is_cancelled(errno : Int) -> Bool = "moonbitlang_async_errno_is_cancelled"

///|
async fn perform_operation(
  spec : OperationSpec,
  context~ : String,
  cancel? : (SubmittedOperation) -> CancellationStatus raise,
) -> SubmittedOperation {
  @coroutine.check_cancellation()
  guard curr_loop.val is Some(evloop)
  let (subscription_id, operation) = evloop.subscribe_operation(
    spec,
    Wake(@coroutine.current_coroutine()),
  )
  try {
    evloop.wait_for_submitted_operation(subscription_id, operation, cancel?)
    if operation.err() is err && err > 0 {
      if errno_is_cancelled(err) {
        raise @coroutine.Cancelled
      } else {
        raise @os_error.OSError(err, context~)
      }
    }
    operation
  } catch {
    err => {
      operation.free()
      raise err
    }
  }
}

///|
fn Backend::cancel_operation(
  backend : Backend,
  operation : SubmittedOperation,
  context~ : String,
) -> CancellationStatus raise {
  backend.thread_pool.cancel(operation.job(), context~)
}
