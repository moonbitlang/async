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
priv struct EventLoop {
  poll : Instance
  fds : Map[@fd_util.Fd, IoHandle]
  pids : Map[Int, @coroutine.Coroutine]
  notify_recv : @fd_util.Fd
  max_worker_count : Int
  mut job_id : Int
  job_queue : @deque.Deque[QueuedJob]
  idle_workers : @deque.Deque[Worker]
  running_workers : Map[Int, Worker]
  jobs : Map[Int, @coroutine.Coroutine]
  timers : @sorted_set.SortedSet[Timer]
}

///|
struct IoHandle {
  mut fd : @fd_util.Fd
  kind : @fd_util.FileKind
  mut events : Int
  mut read : @coroutine.Coroutine?
  mut write : @coroutine.Coroutine?
}

///|
priv struct QueuedJob {
  job_id : Int
  job : Job
}

///|
let curr_loop : Ref[EventLoop?] = @ref.new(None)

///|
priv struct EventLoopHook {
  init : (() -> Unit raise)?
  exit : (() -> Unit raise)?
}

///|
let hooks : Array[EventLoopHook] = []

///|
fn register_hook(init? : () -> Unit raise, exit? : () -> Unit raise) -> Unit {
  hooks.push({ init, exit })
}

///|
pub fn with_event_loop(f : async () -> Unit) -> Unit raise {
  guard curr_loop.val is None
  let (notify_recv, notify_send) = @fd_util.pipe("initialze runtime")
  try {
    @fd_util.set_nonblocking(notify_recv, context="initialize runtime")
    @fd_util.set_blocking(notify_send, context="initialize runtime")
  } catch {
    err => {
      @fd_util.close(notify_recv, kind=Pipe, context="initialize runtime")
      @fd_util.close(notify_send, kind=Pipe, context="initialize runtime")
      raise err
    }
  }
  defer {
    @fd_util.close(notify_recv, context="initialize runtime") catch {
      _ => ()
    }
    @fd_util.close(notify_send, context="initialize runtime") catch {
      _ => ()
    }
  }
  init_thread_pool_ffi(notify_send)
  defer destroy_thread_pool()
  let evloop = {
    poll: Instance::new(),
    fds: {},
    pids: {},
    notify_recv,
    max_worker_count: 1024,
    job_id: 0,
    job_queue: @deque.new(),
    idle_workers: @deque.new(),
    running_workers: {},
    jobs: {},
    timers: @sorted_set.new(),
  }
  defer evloop.poll.destroy()
  evloop.poll.register(notify_recv, prev_events=NoEvent, new_events=ReadEvent)
  |> ignore
  defer (evloop.poll.remove(notify_recv, events=ReadEvent) catch { _ => () })
  curr_loop.val = Some(evloop)
  for hook in hooks {
    if hook.init is Some(init) {
      init()
    }
  }
  defer {
    curr_loop.val = None
  }
  let main = @coroutine.spawn(f)
  evloop.run_forever()
  main.unwrap()
}

///|
fn EventLoop::poll(self : Self) -> Unit raise {
  let timeout = if @coroutine.has_immediately_ready_task() {
    0
  } else if self.timers.iter().head() is Some(timer) {
    @cmp.maximum(0, (timer.expire_time - @time.ms_since_epoch()).to_int())
  } else {
    -1
  }
  let n = self.poll.wait(timeout~)
  if n < 0 {
    @os_error.check_errno("runtime internal: poll_wait")
  }
  let now = @time.ms_since_epoch()
  for timer in self.timers {
    if timer.expire_time <= now {
      timer.coro.wake()
    } else {
      break
    }
  }
  for i in 0..<n {
    let event = get_event(i)
    let events = event.events()
    let fd = event.fd()
    if (events & ProcessEvent) != 0 {
      if self.pids.get(fd) is Some(coro) {
        coro.wake()
      }
    } else if fd == self.notify_recv {
      while fetch_completion_ffi(self.notify_recv) is job_id && job_id >= 0 {
        guard self.running_workers.get(job_id) is Some(worker)
        self.running_workers.remove(job_id)
        match self.job_queue.pop_front() {
          None => self.idle_workers.push_back(worker)
          Some(job) => {
            self.running_workers[job.job_id] = worker
            wake_worker(worker, job.job_id, job.job)
          }
        }
        if self.jobs.get(job_id) is Some(coro) {
          coro.wake()
        }
      } else {
        if not(@os_error.is_nonblocking_io_error()) {
          @os_error.check_errno("runtime internal: failed to get completed job")
        }
      }
    } else if self.fds.get(fd) is Some(handle) {
      if (events & ReadEvent) != 0 && handle.read is Some(coro) {
        coro.wake()
      }
      if (events & WriteEvent) != 0 && handle.write is Some(coro) {
        coro.wake()
      }
    }
  }
}

///|
fn EventLoop::cleanup(self : Self) -> Unit raise {
  for hook in hooks {
    if hook.exit is Some(exit) {
      exit()
    }
  }
  for fd, handle in self.fds {
    if handle.read is Some(coro) {
      coro.cancel()
    }
    if handle.write is Some(coro) {
      coro.cancel()
    }
    if not(handle.events is NoEvent) {
      // if `poll_register` fails, `handle.events` may be `NoEvent`,
      // in this case we have never added it to the poller,
      // so we must not remove it from the poller here
      self.poll.remove(fd, events=handle.events)
    }
    @fd_util.close(
      fd,
      kind=handle.kind,
      context="runtime internal: close leaking fd",
    )
  }
  self.fds.clear()
  for _, coro in self.jobs {
    coro.cancel()
  }
  for pid, coro in self.pids {
    coro.cancel()
    self.poll.remove_pid(pid)
  }
  self.pids.clear()
}

///|
fn EventLoop::run_forever(self : Self) -> Unit raise {
  let poll_coro = @coroutine.spawn(fn() {
    while not(@coroutine.no_more_work() && self.running_workers.is_empty()) {
      self.poll() catch {
        @os_error.OSError(_) as err if err.is_EINTR() => continue
        err => raise err
      }
      @coroutine.pause()
    }
  })
  @coroutine.reschedule()
  self.cleanup()
  poll_coro.unwrap()
}

///|
pub async fn sleep(duration : Int) -> Unit {
  guard curr_loop.val is Some(evloop)
  let timer = Timer::new(duration, @coroutine.current_coroutine())
  evloop.timers.add(timer)
  defer evloop.timers.remove(timer)
  @coroutine.suspend()
}

///|
pub fn IoHandle::from_fd(
  fd : @fd_util.Fd,
  kind~ : @fd_util.FileKind,
) -> IoHandle {
  guard curr_loop.val is Some(evloop)
  guard evloop.fds.get(fd) is None
  let handle = { fd, kind, read: None, write: None, events: NoEvent }
  evloop.fds[fd] = handle
  handle
}

///|
pub fn IoHandle::from_existing_fd(fd : @fd_util.Fd) -> IoHandle {
  guard curr_loop.val is Some(evloop)
  guard evloop.fds.get(fd) is Some(io)
  io
}

///|
pub fn IoHandle::fd(handle : IoHandle) -> @fd_util.Fd {
  handle.fd
}

///|
pub fn IoHandle::kind(handle : IoHandle) -> @fd_util.FileKind {
  handle.kind
}

///|
fn IoHandle::prepare_read(handle : IoHandle) -> Unit raise {
  guard curr_loop.val is Some(evloop)
  guard handle.fd >= 0 else { abort("file descriptor already closed") }
  if (handle.events & ReadEvent) == 0 {
    evloop.poll.register(
      handle.fd,
      prev_events=handle.events,
      new_events=ReadEvent,
      oneshot=false,
    )
    handle.events = handle.events | ReadEvent
  }
}

///|
async fn IoHandle::wait_read(handle : IoHandle) -> Unit {
  guard (handle.events & ReadEvent) != 0
  guard handle.fd >= 0 else { abort("file descriptor already closed") }
  guard handle.read is None
  handle.read = Some(@coroutine.current_coroutine())
  defer {
    handle.read = None
  }
  @coroutine.suspend()
}

///|
fn IoHandle::prepare_write(handle : IoHandle) -> Unit raise {
  guard curr_loop.val is Some(evloop)
  guard handle.fd >= 0 else { abort("file descriptor already closed") }
  if (handle.events & WriteEvent) == 0 {
    evloop.poll.register(
      handle.fd,
      prev_events=handle.events,
      new_events=WriteEvent,
      oneshot=false,
    )
    handle.events = handle.events | WriteEvent
  }
}

///|
async fn IoHandle::wait_write(handle : IoHandle) -> Unit {
  guard (handle.events & WriteEvent) != 0
  guard handle.fd >= 0 else { abort("file descriptor already closed") }
  guard handle.write is None
  let coro = @coroutine.current_coroutine()
  handle.write = Some(coro)
  defer {
    handle.write = None
  }
  @coroutine.suspend()
}

///|
/// Detach a file descriptor from the event loop,
/// but does not close the file descriptor itself.
/// The underlying file descriptor is returned.
pub fn IoHandle::detach_from_event_loop(handle : IoHandle) -> @fd_util.Fd {
  guard curr_loop.val is Some(evloop)
  guard handle.fd >= 0 else { -1 }
  evloop.fds.remove(handle.fd)
  if not(handle.events is NoEvent) {
    evloop.poll.remove(handle.fd, events=handle.events) catch {
      err => abort("detach \{handle.fd} from loop: \{err}")
    }
  }
  let fd = handle.fd
  handle.fd = -1
  fd
}

///|
/// Close a file descriptor and detach it from the event loop.
/// This function is idempotent: it is safe to call `.close()` multiple times.
pub fn IoHandle::close(handle : IoHandle) -> Unit {
  let fd = handle.detach_from_event_loop()
  if fd >= 0 {
    @fd_util.close(fd, kind=handle.kind, context="") catch {
      _ => ()
    }
  }
}

///|
async fn perform_job_in_worker(
  job : Job,
  context~ : String,
  allow_cancel? : Bool = false,
) -> Int {
  guard curr_loop.val is Some(evloop)
  let job_id = evloop.job_id
  evloop.job_id += 1
  match evloop.idle_workers.pop_front() {
    None if evloop.running_workers.length() > evloop.max_worker_count =>
      evloop.job_queue.push_back({ job_id, job })
    None => {
      let worker = spawn_worker(job_id, job)
      evloop.running_workers[job_id] = worker
    }
    Some(worker) => {
      evloop.running_workers[job_id] = worker
      wake_worker(worker, job_id, job)
    }
  }
  evloop.jobs[job_id] = @coroutine.current_coroutine()
  defer evloop.jobs.remove(job_id)
  if allow_cancel {
    @coroutine.suspend()
  } else {
    @coroutine.protect_from_cancel(@coroutine.suspend)
  }
  if job.err() > 0 {
    raise @os_error.OSError(job.err(), context~)
  } else {
    job.ret()
  }
}

///|
#borrow(buf)
extern "C" fn read_ffi(
  fd : @fd_util.Fd,
  buf : FixedArray[Byte],
  offset~ : Int,
  len~ : Int,
) -> Int = "moonbitlang_async_read"

///|
pub async fn IoHandle::read(
  handle : IoHandle,
  buf : FixedArray[Byte],
  offset~ : Int,
  len~ : Int,
  context~ : String,
) -> Int {
  if handle.kind.can_poll() {
    handle.prepare_read()
    let ret = read_ffi(handle.fd, buf, offset~, len~)
    if ret >= 0 {
      @coroutine.pause()
      return ret
    }
    let ret = if @os_error.is_nonblocking_io_error() {
      handle.wait_read()
      read_ffi(handle.fd, buf, offset~, len~)
    } else {
      ret
    }
    if ret < 0 {
      @os_error.check_errno(context)
    }
    ret
  } else {
    let job = Job::read(handle.fd, buf, offset, len, position=-1)
    perform_job_in_worker(job, context~)
  }
}

///|
pub async fn IoHandle::read_at(
  handle : IoHandle,
  buf : FixedArray[Byte],
  offset~ : Int,
  len~ : Int,
  position~ : Int64,
  context~ : String,
) -> Int {
  guard !handle.kind.can_poll()
  let job = Job::read(handle.fd, buf, offset, len, position~)
  perform_job_in_worker(job, context~)
}

///|
#borrow(buf)
extern "C" fn write_ffi(
  fd : @fd_util.Fd,
  buf : Bytes,
  offset~ : Int,
  len~ : Int,
) -> Int = "moonbitlang_async_write"

///|
pub async fn IoHandle::write(
  handle : IoHandle,
  buf : Bytes,
  offset~ : Int,
  len~ : Int,
  context~ : String,
) -> Int {
  if handle.kind.can_poll() {
    handle.prepare_write()
    let ret = write_ffi(handle.fd, buf, offset~, len~)
    if ret >= 0 {
      @coroutine.pause()
      return ret
    }
    let ret = if @os_error.is_nonblocking_io_error() {
      handle.wait_write()
      write_ffi(handle.fd, buf, offset~, len~)
    } else {
      ret
    }
    if ret < 0 {
      @os_error.check_errno(context)
    }
    ret
  } else {
    let job = Job::write(handle.fd, buf, offset, len, position=-1)
    perform_job_in_worker(job, context~)
  }
}

///|
pub async fn IoHandle::write_at(
  handle : IoHandle,
  buf : Bytes,
  offset~ : Int,
  len~ : Int,
  position~ : Int64,
  context~ : String,
) -> Unit {
  guard !handle.kind.can_poll()
  let job = Job::write(handle.fd, buf, offset, len, position~)
  perform_job_in_worker(job, context~) |> ignore
}

///|
pub async fn spawn(
  path : @os_string.OsString,
  args : FixedArray[@os_string.OsString?],
  env~ : FixedArray[@os_string.OsString?],
  stdin~ : @fd_util.Fd,
  stdout~ : @fd_util.Fd,
  stderr~ : @fd_util.Fd,
  cwd~ : @os_string.OsString?,
  context~ : String,
) -> Int {
  perform_job_in_worker(
    Job::spawn(path, args, env, stdin, stdout, stderr, cwd),
    context~,
  )
}

///|
pub async fn wait_pid(pid : Int) -> Unit {
  guard curr_loop.val is Some(evloop)
  let alt_id = match evloop.poll.register_pid(pid) {
    Running(id) => id
    Stopped => return
  }
  guard evloop.pids.get(alt_id) is None
  evloop.pids[alt_id] = @coroutine.current_coroutine()
  defer {
    evloop.pids.remove(alt_id)
    evloop.poll.remove_pid(alt_id)
  }
  @coroutine.suspend()
}
