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
  fds : Map[Int, FdHandle]
  pids : Map[Int, @coroutine.Coroutine]
  notify_recv : Int
  max_worker_count : Int
  job_queue : @deque.Deque[JobForWorker]
  idle_workers : @deque.Deque[Worker]
  running_workers : Map[Int, Worker]
  jobs : Map[Int, @coroutine.Coroutine]
  timers : @sorted_set.SortedSet[Timer]
}

///|
priv struct FdHandle {
  mut events : Int
  mut read : @coroutine.Coroutine?
  mut write : @coroutine.Coroutine?
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
pub fn register_hook(
  init? : () -> Unit raise,
  exit? : () -> Unit raise,
) -> Unit {
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
      @fd_util.close(notify_recv, context="initialize runtime")
      @fd_util.close(notify_send, context="initialize runtime")
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
  try {
    defer {
      curr_loop.val = None
    }
    let main = @coroutine.spawn(f)
    evloop.run_forever()
    main.unwrap()
  } catch {
    err => {
      for hook in hooks {
        if hook.exit is Some(exit) {
          exit()
        }
      }
      raise err
    }
  }
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
            self.running_workers[job.id()] = worker
            wake_worker(worker, job)
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
    @fd_util.close(fd, context="runtime internal: close leaking fd")
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
        err => {
          self.cleanup()
          raise err
        }
      }
      @coroutine.pause()
    } else {
      self.cleanup()
    }
  })
  @coroutine.reschedule()
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
fn prepare_fd_read(fd : Int) -> FdHandle raise {
  guard curr_loop.val is Some(evloop)
  let handle = match evloop.fds.get(fd) {
    None => {
      let handle = { read: None, write: None, events: NoEvent }
      evloop.fds[fd] = handle
      handle
    }
    Some(handle) => handle
  }
  if (handle.events & ReadEvent) == 0 {
    evloop.poll.register(
      fd,
      prev_events=handle.events,
      new_events=ReadEvent,
      oneshot=false,
    )
    handle.events = handle.events | ReadEvent
  }
  handle
}

///|
async fn FdHandle::wait_read(handle : FdHandle) -> Unit {
  guard (handle.events & ReadEvent) != 0
  guard handle.read is None
  handle.read = Some(@coroutine.current_coroutine())
  defer {
    handle.read = None
  }
  @coroutine.suspend()
}

///|
fn prepare_fd_write(fd : Int) -> FdHandle raise {
  guard curr_loop.val is Some(evloop)
  let handle = match evloop.fds.get(fd) {
    None => {
      let handle = { read: None, write: None, events: NoEvent }
      evloop.fds[fd] = handle
      handle
    }
    Some(handle) => handle
  }
  if (handle.events & WriteEvent) == 0 {
    evloop.poll.register(
      fd,
      prev_events=handle.events,
      new_events=WriteEvent,
      oneshot=false,
    )
    handle.events = handle.events | WriteEvent
  }
  handle
}

///|
async fn FdHandle::wait_write(handle : FdHandle) -> Unit {
  guard (handle.events & WriteEvent) != 0
  guard handle.write is None
  let coro = @coroutine.current_coroutine()
  handle.write = Some(coro)
  defer {
    handle.write = None
  }
  @coroutine.suspend()
}

///|
pub fn close_fd(fd : Int) -> Unit {
  guard curr_loop.val is Some(evloop)
  if evloop.fds.get(fd) is Some(handle) {
    evloop.fds.remove(fd)
    if not(handle.events is NoEvent) {
      evloop.poll.remove(fd, events=handle.events) catch {
        err => abort("detach \{fd} from loop: \{err}")
      }
    }
  }
  @fd_util.close(fd, context="") catch {
    _ => ()
  }
}

///|
async fn perform_job_in_worker(
  job : JobForWorker,
  context~ : String,
  allow_cancel? : Bool = false,
) -> Int {
  guard curr_loop.val is Some(evloop)
  match evloop.idle_workers.pop_front() {
    None if evloop.running_workers.length() > evloop.max_worker_count =>
      evloop.job_queue.push_back(job)
    None => {
      let worker = spawn_worker(job)
      evloop.running_workers[job.id()] = worker
    }
    Some(worker) => {
      evloop.running_workers[job.id()] = worker
      wake_worker(worker, job)
    }
  }
  evloop.jobs[job.id()] = @coroutine.current_coroutine()
  defer evloop.jobs.remove(job.id())
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
  fd : Int,
  buf : FixedArray[Byte],
  offset~ : Int,
  len~ : Int,
) -> Int = "moonbitlang_async_read"

///|
pub async fn read(
  fd : Int,
  buf : FixedArray[Byte],
  offset~ : Int,
  len~ : Int,
  can_poll~ : Bool,
  context~ : String,
) -> Int {
  if can_poll {
    let handle = prepare_fd_read(fd)
    let ret = read_ffi(fd, buf, offset~, len~)
    let ret = if ret < 0 && @os_error.is_nonblocking_io_error() {
      handle.wait_read()
      read_ffi(fd, buf, offset~, len~)
    } else {
      @coroutine.pause()
      ret
    }
    if ret < 0 {
      @os_error.check_errno(context)
    }
    ret
  } else {
    let job = JobForWorker::read(fd, buf, offset, len)
    perform_job_in_worker(job, context~)
  }
}

///|
#borrow(buf)
extern "C" fn write_ffi(
  fd : Int,
  buf : Bytes,
  offset~ : Int,
  len~ : Int,
) -> Int = "moonbitlang_async_write"

///|
pub async fn write(
  fd : Int,
  buf : Bytes,
  offset~ : Int,
  len~ : Int,
  can_poll~ : Bool,
  context~ : String,
) -> Int {
  if can_poll {
    let handle = prepare_fd_write(fd)
    let ret = write_ffi(fd, buf, offset~, len~)
    let ret = if ret < 0 && @os_error.is_nonblocking_io_error() {
      handle.wait_write()
      write_ffi(fd, buf, offset~, len~)
    } else {
      @coroutine.pause()
      ret
    }
    if ret < 0 {
      @os_error.check_errno(context)
    }
    ret
  } else {
    let job = JobForWorker::write(fd, buf, offset, len)
    perform_job_in_worker(job, context~)
  }
}

///|
pub async fn spawn(
  path : Bytes,
  args : FixedArray[Bytes?],
  env~ : FixedArray[Bytes?],
  stdin~ : Int,
  stdout~ : Int,
  stderr~ : Int,
  cwd~ : Bytes?,
  context~ : String,
) -> Int {
  perform_job_in_worker(
    JobForWorker::spawn(path, args, env, stdin, stdout, stderr, cwd),
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
