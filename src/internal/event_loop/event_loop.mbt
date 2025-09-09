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
  pids : Map[Int, ProcessHandle]
  notify_recv : Int
  max_worker_count : Int
  job_queue : @deque.Deque[JobForWorker]
  idle_workers : @deque.Deque[Worker]
  running_workers : Map[Int, Worker]
  jobs : Map[Int, @coroutine.Coroutine]
}

///|
priv enum EventStatus {
  NotSure
  Ready
  Waiting(@coroutine.Coroutine)
}

///|
priv struct FdHandle {
  mut events : Int
  mut read : EventStatus
  mut write : EventStatus
}

///|
priv struct ProcessHandle {
  mut result : Int
  waiter : @coroutine.Coroutine
}

///|
let curr_loop : Ref[EventLoop?] = @ref.new(None)

///|
priv struct EventLoopHook {
  init : (() -> Unit)?
  exit : (() -> Unit)?
}

///|
let hooks : Array[EventLoopHook] = []

///|
pub fn register_hook(init? : () -> Unit, exit? : () -> Unit) -> Unit {
  hooks.push({ init, exit })
}

///|
pub fn with_event_loop(f : async () -> Unit raise) -> Unit raise {
  guard curr_loop.val is None
  let (notify_recv, notify_send) = @fd_util.pipe()
  try {
    @fd_util.set_nonblocking(notify_recv)
    @fd_util.set_blocking(notify_send)
  } catch {
    err => {
      @fd_util.close(notify_recv)
      @fd_util.close(notify_send)
      raise err
    }
  }
  defer {
    @fd_util.close(notify_recv) catch {
      _ => ()
    }
    @fd_util.close(notify_send) catch {
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
async fn EventLoop::poll(self : Self) -> Bool raise {
  if @coroutine.no_more_work() && self.running_workers.is_empty() {
    return false
  }
  let timeout = match @coroutine.idle_timeout() {
    Some(t) => t.to_int()
    None => -1
  }
  let n = self.poll.wait(timeout~)
  if n < 0 {
    @os_error.check_errno()
  }
  for i in 0..<n {
    let event = get_event(i)
    let events = event.events()
    let fd = event.fd()
    if (events & ProcessEvent) != 0 {
      if self.pids.get(fd) is Some(handle) {
        let result = @ref.new(0)
        if event.pid_status(result) < 0 {
          @os_error.check_errno()
        }
        handle.result = result.val
        self.pids.remove(fd)
        handle.waiter.wake()
      }
      self.poll.remove_pid(fd)
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
          self.jobs.remove(job_id)
          coro.wake()
        }
      } else {
        if not(@os_error.is_nonblocking_io_error()) {
          @os_error.check_errno()
        }
      }
    } else if self.fds.get(fd) is Some(handle) {
      // There is one corner case here: to support precise timer,
      // we perform a `@coroutine.reschedule` immediately after polling.
      // However, if a file descriptor is closed during this rescheduling,
      // it will be removed from `self.fds`, but we can still see it here,
      // because the poll returns *before* the close
      if (events & ReadEvent) != 0 {
        match handle.read {
          Ready => ()
          NotSure => handle.read = Ready
          Waiting(coro) => {
            handle.read = NotSure
            coro.wake()
          }
        }
      }
      if (events & WriteEvent) != 0 {
        match handle.write {
          Ready => ()
          NotSure => handle.write = Ready
          Waiting(coro) => {
            handle.write = NotSure
            coro.wake()
          }
        }
      }
    }
  }
  @coroutine.pause()
  true
}

///|
fn EventLoop::run_forever(self : Self) -> Unit raise {
  let _ = @coroutine.spawn(fn() {
    while self.poll() {

    }
  })
  @coroutine.reschedule()
  for fd, handle in self.fds {
    guard not(handle.read is Waiting(_)) && not(handle.write is Waiting(_))
    if not(handle.events is NoEvent) {
      // if `poll_register` fails, `handle.events` may be `NoEvent`,
      // in this case we have never added it to the poller,
      // so we must not remove it from the poller here
      self.poll.remove(fd, events=handle.events) catch {
        err => abort("detach \{fd} from loop: \{err}")
      }
    }
    @fd_util.close(fd)
  }
  guard self.pids.is_empty()
  self.fds.clear()
}

///|
fn prepare_fd_read(fd : Int) -> Unit raise {
  guard curr_loop.val is Some(evloop)
  let handle = match evloop.fds.get(fd) {
    None => {
      let handle = { read: NotSure, write: NotSure, events: NoEvent }
      evloop.fds[fd] = handle
      handle
    }
    Some(handle) => handle
  }
  guard not(handle.read is Waiting(_))
  if (handle.events & ReadEvent) == 0 {
    evloop.poll.register(
      fd,
      prev_events=handle.events,
      new_events=ReadEvent,
      oneshot=false,
    )
    handle.events = handle.events | ReadEvent
  } else {
    handle.read = NotSure
  }
}

///|
async fn wait_fd_read(fd : Int) -> Unit raise {
  guard curr_loop.val is Some(evloop)
  guard evloop.fds.get(fd) is Some(handle)
  guard (handle.events & ReadEvent) != 0
  if handle.read is Ready {
    handle.read = NotSure
    return
  }
  handle.read = Waiting(@coroutine.current_coroutine())
  @coroutine.suspend() catch {
    err => {
      if handle.read is Waiting(_) {
        handle.read = NotSure
      }
      raise err
    }
  }
}

///|
fn prepare_fd_write(fd : Int) -> Unit raise {
  guard curr_loop.val is Some(evloop)
  let handle = match evloop.fds.get(fd) {
    None => {
      let handle = { read: NotSure, write: NotSure, events: NoEvent }
      evloop.fds[fd] = handle
      handle
    }
    Some(handle) => handle
  }
  guard not(handle.write is Waiting(_))
  if (handle.events & WriteEvent) == 0 {
    evloop.poll.register(
      fd,
      prev_events=handle.events,
      new_events=WriteEvent,
      oneshot=false,
    )
    handle.events = handle.events | WriteEvent
  } else {
    handle.write = NotSure
  }
}

///|
async fn wait_fd_write(fd : Int) -> Unit raise {
  guard curr_loop.val is Some(evloop)
  guard evloop.fds.get(fd) is Some(handle)
  guard (handle.events & WriteEvent) != 0
  if handle.write is Ready {
    handle.write = NotSure
    return
  }
  let coro = @coroutine.current_coroutine()
  handle.write = Waiting(coro)
  ignore(@coroutine.suspend()) catch {
    err => {
      if handle.write is Waiting(_) {
        handle.write = NotSure
      }
      raise err
    }
  }
}

///|
async fn wait_pid(pid : Int) -> Int raise {
  guard curr_loop.val is Some(evloop)
  let alt_id = match evloop.poll.register_pid(pid) {
    Running(id) => id
    Stopped(ret) => return ret
  }
  guard evloop.pids.get(alt_id) is None
  let handle = { result: 0, waiter: @coroutine.current_coroutine() }
  evloop.pids[alt_id] = handle
  @coroutine.suspend() catch {
    err => {
      evloop.pids.remove(alt_id)
      evloop.poll.remove_pid(alt_id)
      raise err
    }
  }
  handle.result
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
  @fd_util.close(fd) catch {
    _ => ()
  }
}

///|
async fn perform_job_in_worker(
  job : JobForWorker,
  allow_cancel? : Bool = false,
) -> Int raise {
  guard curr_loop.val is Some(evloop)
  match evloop.idle_workers.pop_front() {
    None if evloop.running_workers.size() > evloop.max_worker_count =>
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
  if allow_cancel {
    @coroutine.suspend() catch {
      err => {
        evloop.jobs.remove(job.id())
        raise err
      }
    }
  } else {
    @coroutine.protect_from_cancel(@coroutine.suspend)
  }
  if job.err() > 0 {
    raise @os_error.OSError(job.err())
  } else {
    job.ret()
  }
}

///|
pub async fn perform_job(job : Job) -> Int raise {
  match job {
    Sleep(t) => perform_job_in_worker(JobForWorker::sleep(t))
    Read(fd~, buf~, offset~, len~, can_poll~) =>
      if can_poll {
        prepare_fd_read(fd)
        let ret = read_ffi(fd, buf, offset~, len~)
        let ret = if ret < 0 && @os_error.is_nonblocking_io_error() {
          wait_fd_read(fd)
          read_ffi(fd, buf, offset~, len~)
        } else {
          @coroutine.pause()
          ret
        }
        if ret < 0 {
          @os_error.check_errno()
        }
        ret
      } else {
        let job = JobForWorker::read(fd, buf, offset, len)
        perform_job_in_worker(job)
      }
    Write(fd~, buf~, offset~, len~, can_poll~) =>
      if can_poll {
        prepare_fd_write(fd)
        let ret = write_ffi(fd, buf, offset~, len~)
        let ret = if ret < 0 && @os_error.is_nonblocking_io_error() {
          wait_fd_write(fd)
          write_ffi(fd, buf, offset~, len~)
        } else {
          @coroutine.pause()
          ret
        }
        if ret < 0 {
          @os_error.check_errno()
        }
        ret
      } else {
        let job = JobForWorker::write(fd, buf, offset, len)
        perform_job_in_worker(job)
      }
    Open(path~, flags~, mode~) =>
      perform_job_in_worker(JobForWorker::open(path, flags, mode))
    Stat(path~, out~) => perform_job_in_worker(JobForWorker::stat(path, out))
    Access(path~, amode~) =>
      perform_job_in_worker(JobForWorker::access(path, amode))
    Remove(path~) => perform_job_in_worker(JobForWorker::remove(path))
    Mkdir(path~, mode~) =>
      perform_job_in_worker(JobForWorker::mkdir(path, mode))
    Rmdir(path~) => perform_job_in_worker(JobForWorker::rmdir(path))
    Readdir(dir~, out~) =>
      perform_job_in_worker(JobForWorker::readdir(dir, out))
    Spawn(path~, args~, env~, stdin~, stdout~, stderr~, cwd~) =>
      perform_job_in_worker(
        JobForWorker::spawn(path, args, env, stdin, stdout, stderr, cwd),
      )
    Recvfrom(sock~, buf~, offset~, len~, addr~) => {
      prepare_fd_read(sock)
      let ret = recvfrom_ffi(sock, buf, offset~, len~, addr~)
      let ret = if ret < 0 && @os_error.is_nonblocking_io_error() {
        wait_fd_read(sock)
        recvfrom_ffi(sock, buf, offset~, len~, addr~)
      } else {
        @coroutine.pause()
        ret
      }
      if ret < 0 {
        @os_error.check_errno()
      }
      ret
    }
    Sendto(sock~, buf~, offset~, len~, addr~) => {
      prepare_fd_write(sock)
      let ret = sendto_ffi(sock, buf, offset~, len~, addr~)
      let ret = if ret < 0 && @os_error.is_nonblocking_io_error() {
        wait_fd_write(sock)
        sendto_ffi(sock, buf, offset~, len~, addr~)
      } else {
        @coroutine.pause()
        ret
      }
      if ret < 0 {
        @os_error.check_errno()
      }
      ret
    }
    Connect(sock~, addr~) => {
      prepare_fd_write(sock)
      if 0 == connect_ffi(sock, addr) {
        return 0
      }
      if @os_error.is_nonblocking_io_error() {
        wait_fd_write(sock)
        let err = get_socket_err(sock)
        if err < 0 {
          @os_error.check_errno()
        } else if err > 0 {
          raise @os_error.OSError(err)
        }
      } else {
        @os_error.check_errno()
      }
      0
    }
    Accept(sock~, addr~) => {
      prepare_fd_read(sock)
      let conn = accept_ffi(sock, addr)
      if conn > 0 {
        conn
      } else if @os_error.is_nonblocking_io_error() {
        wait_fd_read(sock)
        accept_ffi(sock, addr)
      } else {
        @os_error.check_errno()
        -1
      }
    }
    WaitProcess(pid) => wait_pid(pid)
    GetAddrInfo(host~, out~) =>
      perform_job_in_worker(
        JobForWorker::getaddrinfo(host, out),
        allow_cancel=true,
      )
  }
}

///|
#borrow(addr)
extern "C" fn connect_ffi(sock : Int, addr : Bytes) -> Int = "moonbitlang_async_connect"

///|
#borrow(addr_buf)
extern "C" fn accept_ffi(sock : Int, addr_buf : Bytes) -> Int = "moonbitlang_async_accept"

///|
extern "C" fn get_socket_err(sock : Int) -> Int = "moonbitlang_async_getsockerr"

///|
#borrow(buf)
extern "C" fn read_ffi(
  fd : Int,
  buf : FixedArray[Byte],
  offset~ : Int,
  len~ : Int,
) -> Int = "moonbitlang_async_read"

///|
#borrow(buf)
extern "C" fn write_ffi(
  fd : Int,
  buf : Bytes,
  offset~ : Int,
  len~ : Int,
) -> Int = "moonbitlang_async_write"

///|
#borrow(buf, addr)
extern "C" fn recvfrom_ffi(
  fd : Int,
  buf : FixedArray[Byte],
  offset~ : Int,
  len~ : Int,
  addr~ : Bytes,
) -> Int = "moonbitlang_async_recvfrom"

///|
#borrow(buf, addr)
extern "C" fn sendto_ffi(
  fd : Int,
  buf : Bytes,
  offset~ : Int,
  len~ : Int,
  addr~ : Bytes,
) -> Int = "moonbitlang_async_sendto"
