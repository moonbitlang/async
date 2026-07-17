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
pub(all) enum Platform {
  Linux = 0
  MacOS = 1
  Windows = 2
}

///|
#cfg(target="native")
extern "C" fn get_platform() -> Platform = "moonbitlang_async_get_platform"

///|
#cfg(target="wasm")
#unsafe_skip_stub_check
fn get_platform() -> Platform = "moonbitlang/async" "runtime/get_platform"

///|
pub let platform : Platform = get_platform()

///|
priv struct EventLoop {
  bus : EventBus
  fds : Map[@fd_util.Fd, IoHandle]
  extra : PlatformEventLoopExtra
  /// a special file descriptor used to indicate job completion message from thread pool
  notify_recv : @fd_util.Fd
  max_worker_count : Int
  mut job_id : Int
  job_queue : @deque.Deque[QueuedJob]
  idle_workers : @deque.Deque[Worker]
  running_workers : Map[Int, Worker]
  jobs : Map[Int, @coroutine.Coroutine]
  timers : @sorted_set.SortedSet[Timer]
  mut main : @coroutine.Coroutine?
  mut signal_handler : SignalHandler?
  mut killed_by_signal : Int?
  mut blocked_tasks : Int
}

///|
priv struct QueuedJob {
  job_id : Int
  job : Job
}

///|
let curr_loop : Ref[EventLoop?] = Ref(None)

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
fn EventLoop::new() -> EventLoop raise {
  let bus = EventBus::new()
  try {
    let notify_recv = init_thread_pool_ffi(bus)
    if !@fd_util.fd_is_valid(notify_recv) {
      @os_error.check_errno("initialize thread pool")
    }
    let extra = PlatformEventLoopExtra::new()
    {
      bus,
      fds: Map([]),
      extra,
      notify_recv,
      max_worker_count: 1024,
      job_id: 0,
      job_queue: Deque([]),
      idle_workers: Deque([]),
      running_workers: Map([]),
      jobs: Map([]),
      timers: SortedSet([]),
      main: None,
      signal_handler: None,
      killed_by_signal: None,
      blocked_tasks: 0,
    }
  } catch {
    err => {
      bus.destroy()
      raise err
    }
  }
}

///|
fn EventLoop::destroy(evloop : EventLoop) -> Unit {
  evloop.bus.destroy()
  destroy_thread_pool()
  evloop.extra.destroy()
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
  let signal_handler = setup_signal_handler()
  evloop.signal_handler = Some(signal_handler)
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
  evloop.main = Some(main)
  evloop.run_forever()
  main.unwrap()
}

///|
async fn EventLoop::suspend(evloop : EventLoop) -> Unit {
  evloop.blocked_tasks += 1
  defer {
    evloop.blocked_tasks -= 1
  }
  @coroutine.suspend()
}

///|
#cfg(target="native")
using @env {now}

///|
#cfg(target="wasm")
#unsafe_skip_stub_check
fn now() -> UInt64 = "moonbitlang/async" "time/get_ms_since_epoch"

///|
fn EventLoop::wait_for_event(self : EventLoop) -> Int raise {
  // Short-circuit when no timers are pending: this is the common case
  // for IO-only or compute-only tasks that never call `sleep` / `Timer`.
  // Avoids both the iterator-allocation on `self.timers.iter().head()`
  // and the redundant `ms_since_epoch()` + loop below.
  let has_timers = !self.timers.is_empty()
  let timeout = if @coroutine.has_immediately_ready_task() {
    0
  } else if has_timers && self.timers.iter().head() is Some(timer) {
    @cmp.maximum(0, (timer.expire_time - now()).to_int())
  } else {
    -1
  }
  let n = self.bus.wait(timeout~)
  if n < 0 {
    @os_error.check_errno("runtime internal: poll_wait")
  }
  if has_timers {
    let now = now()
    for timer in self.timers {
      if timer.expire_time <= now {
        (timer.callback)()
      } else {
        break
      }
    }
  }
  n
}

///|
fn EventLoop::handle_completed_job(self : Self, job_id : Int) -> Unit {
  // The thread pool pipe may receive job completion event or signal events.
  // Here we encode signal events by setting the most significant bit to one.
  guard (job_id & (1 << 31)) == 0 else {
    // signal
    if self.main is Some(main) {
      main.cancel()
    }
    self.killed_by_signal = Some(job_id ^ (1 << 31))
  }
  guard self.running_workers.get(job_id) is Some(worker)
  self.running_workers.remove(job_id)
  match self.job_queue.pop_front() {
    None => {
      worker.enter_idle()
      self.idle_workers.push_back(worker)
    }
    Some(job) => {
      self.running_workers[job.job_id] = worker
      worker.wake(job.job_id, job.job)
    }
  }
  if self.jobs.get(job_id) is Some(coro) {
    coro.wake()
  }
}

///|
pub let check_fd_leak : Ref[Bool] = Ref(
  @env.get_env_var("MOONBIT_ASYNC_CHECK_FD_LEAK") is Some(_),
)

///|
fn EventLoop::check_fd_leak(self : Self) -> Unit {
  if check_fd_leak.val && !self.fds.is_empty() {
    let leaked_handles = [
      for handle in self.fds.values() => @debug.to_string(handle.kind)
    ].join(", ")
    abort("file descriptor leak detected: \{leaked_handles}")
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
    if handle.read is Waiting(coro) {
      coro.cancel()
    }
    if handle.write is Waiting(coro) {
      coro.cancel()
    }
    @fd_util.close(
      fd,
      kind=handle.kind,
      context="runtime internal: close leaking fd",
    )
  }
  self.check_fd_leak()
  self.fds.clear()
  for _, coro in self.jobs {
    coro.cancel()
  }
  self.extra.cleanup()
  for worker in self.idle_workers {
    worker.free()
  }
}

///|
fn EventLoop::run_forever(self : Self) -> Unit raise {
  try {
    while @coroutine.has_immediately_ready_task() || self.blocked_tasks > 0 {
      self.extra.poll(self) catch {
        @os_error.OSError(_) as err if err.is_EINTR() => continue
        err => raise err
      }
      @coroutine.reschedule()
    }
    let all_coros = @coroutine.all_coroutines().iter()
    let all_coros = match self.signal_handler {
      Some(SigwaitHandler(sigwait_task)) =>
        all_coros.filter(coro => coro != sigwait_task)
      None | Some(ConsoleControlHandler) => all_coros
    }
    let all_coros = all_coros.map(coro => coro.loc.to_string()).collect()
    if all_coros.length() > 0 {
      println(
        "Dead lock detected. Tasks spawned at the following locations are still alive: \{to_repr(all_coros)}",
      )
      panic()
    }
  } catch {
    err => {
      Ref::protect(check_fd_leak, false, () => self.cleanup())
      // In case the event loop has encountered some fatal error,
      // propagate the error to relevant coroutines.
      while @coroutine.has_immediately_ready_task() || self.blocked_tasks > 0 {
        @coroutine.reschedule()
      }
      raise err
    }
  } noraise {
    _ => self.cleanup()
  }
}

///|
priv enum CancellationStatus {
  NoWait
  NeedWait
  RetryLater
}

///|
/// Generic function for performing cancellation on an IO operation.
/// `cancel_func` performs the cancellation work under the hood.
/// For Windows IOCP/thread pool operations, the OS/thread pool hold references to user objects.
/// We must wait for the completion of the operation before dropping those user objects,
/// even in case of cancellation.
async fn wait_for_cancellation(
  cancel_func : () -> CancellationStatus raise,
) -> Unit {
  guard curr_loop.val is Some(evloop)
  try cancel_func() catch {
    err => {
      // The cancellation operation itself failed.
      // Give up the cancellation and wait for completion normally.
      @coroutine.protect_from_cancel(
        () => evloop.suspend(),
        resume_on_cancel=true,
      )
      raise err
    }
  } noraise {
    NeedWait =>
      // The cancellation operation has succeeded,
      // but the thread pool or OS may need some more time to finish all the cleanup.
      // So wait for the completion of the cleanup process here.
      @coroutine.protect_from_cancel(
        () => evloop.suspend(),
        resume_on_cancel=true,
      )
    NoWait =>
      // The cancellation operation has succeeded,
      // and the cancelled operation has already terminated.
      // Return immediately here.
      ()
    RetryLater => {
      // Due to some inherent race condition, the cancellaion attempt did not succeed.
      // Retry again after a small timeout.
      @coroutine.protect_from_cancel(() => sleep(10), resume_on_cancel=true)
      wait_for_cancellation(cancel_func)
    }
  }
}

///|
async fn EventLoop::wait_for_job(
  evloop : EventLoop,
  job_id : Int,
  cancel? : (Int) -> CancellationStatus raise,
) -> Unit {
  evloop.jobs[job_id] = @coroutine.current_coroutine()
  defer evloop.jobs.remove(job_id)
  match cancel {
    None =>
      @coroutine.protect_from_cancel(
        () => evloop.suspend(),
        resume_on_cancel=true,
      )
    Some(cancel_func) =>
      evloop.suspend() catch {
        _ =>
          // The cancellation error is swallowed here,
          // because in case the operation completed before cancellation,
          // we need to return the result normally to retain cancellation safety
          // and avoid data loss.
          // In case the cancellation succeeded,
          // the underlying operation itself should report cancelled status properly
          // via error code (`EINTR` or `ERROR_OPERATION_ABORTED`)
          wait_for_cancellation(() => cancel_func(job_id))
      }
  }
}

///|
#cfg(target="native")
extern "C" fn errno_is_cancelled(errno : Int) -> Bool = "moonbitlang_async_errno_is_cancelled"

///|
#cfg(target="wasm")
#unsafe_skip_stub_check
fn errno_is_cancelled(errno : Int) -> Bool = "moonbitlang/async" "thread_pool/errno_is_cancelled"

///|
async fn perform_job_in_worker(
  job : Job,
  context~ : String,
  cancel? : (Int) -> CancellationStatus raise,
) -> Int {
  @coroutine.check_cancellation()
  guard curr_loop.val is Some(evloop)
  let job_id = evloop.job_id
  evloop.job_id += 1
  match evloop.idle_workers.pop_front() {
    None if evloop.running_workers.length() >= evloop.max_worker_count =>
      evloop.job_queue.push_back({ job_id, job })
    None => {
      let worker = Worker::spawn(job_id, job)
      evloop.running_workers[job_id] = worker
    }
    Some(worker) => {
      evloop.running_workers[job_id] = worker
      worker.wake(job_id, job)
    }
  }
  evloop.wait_for_job(job_id, cancel?)
  if job.err() is err && err > 0 {
    if @coroutine.is_being_cancelled() && errno_is_cancelled(err) {
      raise @coroutine.Cancelled
    } else {
      raise @os_error.OSError(err, context~)
    }
  } else {
    job.copy_output()
    job.ret()
  }
}

///|
fn EventLoop::cancel_job_in_worker(
  evloop : EventLoop,
  job_id : Int,
  context~ : String,
) -> CancellationStatus raise {
  if evloop.running_workers.get(job_id) is Some(worker) {
    worker.cancel(context~)
  } else {
    NoWait
  }
}
