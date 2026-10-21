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
pub using @env_util {platform}

///|
priv struct EventLoop {
  bus : EventBus
  fds : Map[@fd_util.Fd, IoHandle]
  extra : PlatformEventLoopExtra
  /// a special file descriptor used to indicate job completion message from thread pool
  notify_recv : @fd_util.Fd
  max_worker_count : Int32
  mut job_id : Int32
  job_queue : Set[QueuedJob]
  idle_workers : @deque.Deque[Worker]
  running_workers : Map[Int32, Worker]
  jobs : Map[Int32, @coroutine.Coroutine]
  timers : @sorted_set.SortedSet[Timer]
  mut main : @coroutine.Coroutine?
  mut killed_by_signal : Int32?
  mut blocked_tasks : Int32
}

///|
priv struct QueuedJob {
  job_id : Int32
  job : Job
  waiter : @coroutine.Coroutine
}

///|
impl Eq for QueuedJob with fn equal(x, y) {
  x.job_id == y.job_id
}

///|
impl Hash for QueuedJob with fn hash_combine(job, hasher) {
  Hash::hash_combine(job.job_id, hasher)
}

///|
// An intermediate type compiled to `void*` on C backend.
// Used to work around `-Wincompatible-pointer-types` from the C compiler.
priv type CoreEventLoop

///|
#warnings("-alert_internal")
fn CoreEventLoop::from_impl(
  scheduler : @runtime_internal.CurrentEventLoop,
) -> CoreEventLoop = "%identity"

///|
fn from_core_loop(x : CoreEventLoop) -> Ref[EventLoop?] = "%identity"

///|
// Here the cast is decomposed into two parts: core type -> void* -> our type.
// This works around `-Wincompatible-pointer-types` from the C compiler.
// This is hacky, but the whole runtime sharing mechanism is a big temporary hack,
// so we choose to live with it here.
#warnings("-alert_internal")
let curr_loop : Ref[EventLoop?] = from_core_loop(
  CoreEventLoop::from_impl(@runtime_internal.get_current_event_loop()),
)

///|
#cfg(target="native")
pub fn set_external_event_loop(
  extloop : &@external_loop_integration.ExternalEventLoop,
) -> Unit {
  @core_async.set_external_event_loop(extloop)
}

///|
#warnings("-alert_internal")
pub using @runtime_internal {
  register_hook,
  set_deadlock_handler,
  with_event_loop,
}

///|
async fn EventLoop::suspend(evloop : EventLoop) -> Unit noraise {
  evloop.blocked_tasks += 1
  defer {
    evloop.blocked_tasks -= 1
  }
  @coroutine.suspend()
}

///|
async fn EventLoop::suspend_check_cancel(
  evloop : EventLoop,
) -> @coroutine.SuspendResult noraise + nocancel {
  evloop.blocked_tasks += 1
  defer {
    evloop.blocked_tasks -= 1
  }
  @coroutine.suspend_check_cancel()
}

///|
pub using @core_async {now}

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
) -> Unit nocancel {
  guard! curr_loop.val is Some(evloop)
  let status = {
    errdefer @coroutine.protect_from_cancel(() => evloop.suspend())
    cancel_func()
  }
  match status {
    NeedWait =>
      // The cancellation operation has succeeded,
      // but the thread pool or OS may need some more time to finish all the cleanup.
      // So wait for the completion of the cleanup process here.
      @coroutine.protect_from_cancel(() => evloop.suspend())
    NoWait =>
      // The cancellation operation has succeeded,
      // and the cancelled operation has already terminated.
      // Return immediately here.
      ()
    RetryLater => {
      // Due to some inherent race condition, the cancellaion attempt did not succeed.
      // Retry again after a small timeout.
      @coroutine.protect_from_cancel(() => sleep(10))
      wait_for_cancellation(cancel_func)
    }
  }
}

///|
async fn EventLoop::wait_for_job(
  evloop : EventLoop,
  job_id : Int32,
  cancellable~ : Bool,
  context~ : String,
) -> Unit {
  evloop.jobs[job_id] = @coroutine.current_coroutine()
  defer evloop.jobs.remove(job_id)
  if cancellable {
    match evloop.suspend_check_cancel() {
      Continue => ()
      Cancelled =>
        // The cancellation error is swallowed here,
        // because in case the operation completed before cancellation,
        // we need to return the result normally to retain cancellation safety
        // and avoid data loss.
        // In case the cancellation succeeded,
        // the underlying operation itself should report cancelled status properly
        // via error code (`EINTR` or `ERROR_OPERATION_ABORTED`)
        wait_for_cancellation(() => {
          evloop.cancel_job_in_worker(job_id, context~)
        })
    }
  } else {
    @coroutine.protect_from_cancel(() => evloop.suspend())
  }
}

///|
#cfg(target="native")
extern "C" fn errno_is_cancelled(errno : Int32) -> Bool = "moonbitlang_async_errno_is_cancelled"

///|
#cfg(target="wasm")
#unsafe_skip_stub_check
fn errno_is_cancelled(errno : Int32) -> Bool = "moonbitlang/async" "thread_pool/errno_is_cancelled"

///|
async fn perform_job_in_worker(
  job : Job,
  context~ : String,
  cancellable~ : Bool = false,
) -> Int32 {
  @coroutine.check_cancellation()
  guard! curr_loop.val is Some(evloop)
  let job_id = evloop.job_id
  evloop.job_id += 1
  match evloop.idle_workers.pop_front() {
    None if evloop.running_workers.length() >= evloop.max_worker_count => {
      let waiter = @coroutine.current_coroutine()
      let queued_job = { job_id, job, waiter, }
      evloop.job_queue.add(queued_job)
      match @coroutine.suspend_check_cancel() {
        Continue => ()
        Cancelled if evloop.job_queue.contains(queued_job) => {
          evloop.job_queue.remove(queued_job)
          @coroutine.raise_cancellation_signal()
        }
        Cancelled =>
          // If `queued_job` is already removed, the job must have been submitted already,
          // within the same tick as the cancellation request.
          // In this case, swallow the cancellation to avoid problems. 
          ()
      }
    }
    None => {
      let worker = Worker::spawn(job_id, job)
      evloop.running_workers[job_id] = worker
    }
    Some(worker) => {
      evloop.running_workers[job_id] = worker
      worker.wake(job_id, job)
    }
  }
  evloop.wait_for_job(job_id, cancellable~, context~)
  if job.err() is err && err > 0 {
    if @coroutine.is_being_cancelled() && errno_is_cancelled(err) {
      @coroutine.raise_cancellation_signal()
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
  job_id : Int32,
  context~ : String,
) -> CancellationStatus raise {
  if evloop.running_workers.get(job_id) is Some(worker) {
    worker.cancel(context~)
  } else {
    NoWait
  }
}
