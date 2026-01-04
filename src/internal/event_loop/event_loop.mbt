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
#cfg(not(platform="windows"))
pub const IS_WINDOWS : Bool = false

///|
#cfg(platform="windows")
pub const IS_WINDOWS : Bool = true

///|
#cfg(not(platform="windows"))
priv struct EventLoop {
  poll : Instance
  fds : Map[@fd_util.Fd, IoHandle]
  pids : Map[Int, @coroutine.Coroutine]
  notify_recv : @fd_util.Fd
  notify_send : @fd_util.Fd
  max_worker_count : Int
  mut job_id : Int
  job_queue : @deque.Deque[QueuedJob]
  idle_workers : @deque.Deque[Worker]
  running_workers : Map[Int, Worker]
  jobs : Map[Int, @coroutine.Coroutine]
  timers : @sorted_set.SortedSet[Timer]
}

///|
#cfg(platform="windows")
priv struct EventLoop {
  poll : Instance
  fds : Map[@fd_util.Fd, IoHandle]
  max_worker_count : Int
  mut job_id : Int
  job_queue : @deque.Deque[QueuedJob]
  idle_workers : @deque.Deque[Worker]
  running_workers : Map[Int, Worker]
  jobs : Map[Int, @coroutine.Coroutine]
  timers : @sorted_set.SortedSet[Timer]
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
#cfg(not(platform="windows"))
fn EventLoop::new() -> EventLoop raise {
  let poll = Instance::new()
  let (notify_recv, notify_send) = @fd_util.pipe(
    read_end_is_async=true,
    write_end_is_async=false,
    context="initialze runtime",
  )
  poll.register(notify_recv, prev_events=NoEvent, new_events=ReadEvent) catch {
    err => {
      @fd_util.close(notify_recv, kind=Pipe, context="initialize runtime")
      @fd_util.close(notify_send, kind=Pipe, context="initialize runtime")
      raise err
    }
  }
  init_thread_pool_ffi(notify_send)
  {
    poll,
    fds: {},
    pids: {},
    notify_recv,
    notify_send,
    max_worker_count: 1024,
    job_id: 0,
    job_queue: @deque.new(),
    idle_workers: @deque.new(),
    running_workers: {},
    jobs: {},
    timers: @sorted_set.new(),
  }
}

///|
#cfg(platform="windows")
fn EventLoop::new() -> EventLoop raise {
  let poll = Instance::new()
  init_thread_pool_ffi(poll.0)
  if init_WSA_ffi() != 0 {
    @os_error.check_errno("initialize WSA")
  }
  {
    poll,
    fds: {},
    max_worker_count: 1024,
    job_id: 0,
    job_queue: @deque.new(),
    idle_workers: @deque.new(),
    running_workers: {},
    jobs: {},
    timers: @sorted_set.new(),
  }
}

///|
#cfg(not(platform="windows"))
fn EventLoop::destroy(evloop : EventLoop) -> Unit {
  @fd_util.close(evloop.notify_recv, kind=Pipe, context="initialize runtime") catch {
    _ => ()
  }
  @fd_util.close(evloop.notify_send, kind=Pipe, context="initialize runtime") catch {
    _ => ()
  }
  evloop.poll.remove(evloop.notify_recv, events=ReadEvent) catch {
    _ => ()
  }
  evloop.poll.destroy()
  destroy_thread_pool()
}

///|
#cfg(platform="windows")
fn EventLoop::destroy(evloop : EventLoop) -> Unit {
  evloop.poll.destroy()
  destroy_thread_pool()
  ignore(cleanup_WSA_ffi())
}

///|
pub fn with_event_loop(f : async () -> Unit) -> Unit raise {
  guard curr_loop.val is None
  let evloop = EventLoop::new()
  defer evloop.destroy()
  curr_loop.val = Some(evloop)
  defer {
    curr_loop.val = None
  }
  for hook in hooks {
    if hook.init is Some(init) {
      init()
    }
  }
  let main = @coroutine.spawn(f)
  evloop.run_forever()
  main.unwrap()
}

///|
fn EventLoop::wait_for_event(self : EventLoop) -> Int raise {
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
  n
}

///|
fn EventLoop::handle_completed_job(self : Self, job_id : Int) -> Unit {
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
}

///|
#cfg(not(platform="windows"))
fn EventLoop::poll(self : Self) -> Unit raise {
  let n = self.wait_for_event()
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
        self.handle_completed_job(job_id)
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
#cfg(platform="windows")
fn EventLoop::poll(self : Self) -> Unit raise {
  let n = self.wait_for_event()
  for i in 0..<n {
    let event = get_event(i)
    let fd = event.fd()
    if @fd_util.fd_is_valid(fd) {
      // completed IO operation on a file descriptor
      guard self.fds.get(fd) is Some(_) else {  }
      let result = event.io_result()
      let job_id = result.job_id()
      if self.jobs.get(job_id) is Some(coro) {
        coro.wake()
      }
    } else {
      // custom completion packet from thread pool.
      // Here we use the `dwNumberOfBytesTransferred` field to store job ID
      let job_id = event.bytes_transferred()
      self.handle_completed_job(job_id)
    }
  }
}

///|
#cfg(not(platform="windows"))
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
#cfg(platform="windows")
fn EventLoop::cleanup(self : Self) -> Unit raise {
  for hook in hooks {
    if hook.exit is Some(exit) {
      exit()
    }
  }
  for fd, handle in self.fds {
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
  self.jobs.clear()
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
async fn EventLoop::wait_for_job(
  evloop : EventLoop,
  job_id : Int,
  cancel? : (Int) -> Bool raise,
) -> Unit {
  evloop.jobs[job_id] = @coroutine.current_coroutine()
  defer evloop.jobs.remove(job_id)
  match cancel {
    None => @coroutine.protect_from_cancel(@coroutine.suspend)
    Some(cancel_func) =>
      @coroutine.suspend() catch {
        _ =>
          try cancel_func(job_id) catch {
            err =>
              @coroutine.protect_from_cancel(() => {
                @coroutine.suspend()
                raise err
              })
          } noraise {
            false => ()
            true => @coroutine.protect_from_cancel(@coroutine.suspend)
          }
      }
  }
}

///|
async fn perform_job_in_worker(
  job : Job,
  context~ : String,
  cancel? : (Int) -> Bool raise,
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
  evloop.wait_for_job(job_id, cancel?)
  if job.err() > 0 {
    raise @os_error.OSError(job.err(), context~)
  } else {
    job.ret()
  }
}
