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
fn get_platform() -> Platform = "moonbit_v0" "get_platform"

///|
fn sleep_ms(duration : Int) -> Int = "moonbit_v0" "sleep_ms"

///|
pub let platform : Platform = get_platform()

///|
pub const IS_WINDOWS : Bool = false

///|
pub fn is_windows() -> Bool {
  platform is Windows
}

///|
let _ignore_unused_import : Unit = {
  ignore(@c_buffer.unimplemented)
  ignore(@fd_util.unimplemented)
  ignore(@os_string.unimplemented)
  ignore(@os_error.unimplemented)
}

///|
priv struct EventLoop {
  max_worker_count : Int
  mut job_id : Int
  job_queue : @deque.Deque[QueuedJob]
  idle_workers : @deque.Deque[Worker]
  running_workers : Map[Int, Worker]
  completed_jobs_buffer : FixedArray[Int]
  jobs : Map[Int, @coroutine.Coroutine]
  timers : @sorted_set.SortedSet[Timer]
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
fn EventLoop::new() -> EventLoop {
  init_thread_pool_ffi(@fd_util.invalid_fd)
  {
    max_worker_count: 1024,
    job_id: 0,
    job_queue: @deque.Deque([]),
    idle_workers: @deque.Deque([]),
    running_workers: {},
    completed_jobs_buffer: FixedArray::make(1024, 0),
    jobs: {},
    timers: @sorted_set.SortedSet([]),
  }
}

///|
fn EventLoop::destroy(evloop : EventLoop) -> Unit {
  ignore(evloop)
  destroy_thread_pool()
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
  let main = @coroutine.spawn(() => f())
  evloop.run_forever()
  main.unwrap()
}

///|
pub fn reschedule() -> Unit {
  @coroutine.reschedule()
}

///|
fn EventLoop::poll(self : EventLoop) -> Unit {
  let has_timers = !self.timers.is_empty()
  let timeout = if @coroutine.has_immediately_ready_task() {
    0
  } else if has_timers && self.timers.iter().head() is Some(timer) {
    let timer_timeout = @cmp.maximum(
      0,
      (timer.expire_time - @time.ms_since_epoch()).to_int(),
    )
    if !self.running_workers.is_empty() {
      // Native pollers wake early when the thread-pool notification fd becomes
      // readable. The wasm host currently exposes completion fetching, not an
      // interruptible wait primitive, so poll briefly while worker jobs are
      // outstanding to avoid starving completions behind a later timer.
      @cmp.minimum(timer_timeout, 1)
    } else {
      timer_timeout
    }
  } else if !self.running_workers.is_empty() {
    1
  } else {
    1
  }
  if timeout > 0 {
    ignore(sleep_ms(timeout))
  }
  if has_timers {
    let now = @time.ms_since_epoch()
    let expired = []
    for timer in self.timers {
      if timer.expire_time <= now {
        expired.push(timer)
      } else {
        break
      }
    }
    for timer in expired {
      self.timers.remove(timer)
      (timer.callback)()
    }
  }
  while true {
    let bytes_transferred = fetch_completion_ffi(self.completed_jobs_buffer)
    let n = bytes_transferred / 4
    for i in 0..<n {
      self.handle_completed_job(self.completed_jobs_buffer[i])
    }
    if n < self.completed_jobs_buffer.length() {
      break
    }
  }
}

///|
fn EventLoop::handle_completed_job(self : Self, job_id : Int) -> Unit {
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
fn EventLoop::cleanup(self : Self) -> Unit raise {
  for hook in hooks {
    if hook.exit is Some(exit) {
      exit()
    }
  }
  for _, coro in self.jobs {
    coro.cancel()
  }
  self.jobs.clear()
  for worker in self.idle_workers {
    worker.free()
  }
}

///|
fn EventLoop::run_forever(self : Self) -> Unit raise {
  try {
    while !(@coroutine.no_more_work() && self.running_workers.is_empty()) {
      self.poll()
      @coroutine.reschedule()
    }
  } catch {
    err => {
      Ref::protect(check_fd_leak, false, () => self.cleanup())
      while !@coroutine.no_more_work() {
        @coroutine.reschedule()
      }
      raise err
    }
  } noraise {
    _ => self.cleanup()
  }
}

///|
pub let check_fd_leak : Ref[Bool] = Ref(false)

///|
priv enum CancellationStatus {
  NoWait
  NeedWait
  RetryLater
}

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
  job.complete()
  if job.err() is err && err > 0 {
    if errno_is_cancelled(err) {
      raise @coroutine.Cancelled
    } else {
      raise @os_error.OSError(err, context~)
    }
  } else {
    job.ret()
  }
}

///|
fn errno_is_cancelled(errno : Int) -> Bool = "moonbit_v0" "errno_is_cancelled"

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
      @coroutine.protect_from_cancel(@coroutine.suspend, resume_on_cancel=true)
    Some(cancel_func) =>
      @coroutine.suspend() catch {
        err =>
          for ;; {
            let status = cancel_func(job_id) catch {
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
                if evloop.jobs.get(job_id) is None {
                  break
                }
              }
            }
          }
      }
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
