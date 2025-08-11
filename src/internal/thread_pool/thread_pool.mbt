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
priv struct Worker {
  id : Int64
  job_slot : Ref[Job]
}

///|
pub struct Runtime {
  notify_recv : Int
  priv notify_send : Int
  max_worker_count : Int
  priv job_queue : @deque.T[Job]
  priv idle_workers : @deque.T[Worker]
  priv running_workers : Map[Int, Worker]
}

///|
extern "C" fn init_thread_pool_ffi(notify_send : Int) = "moonbitlang_async_init_thread_pool"

///|
pub fn Runtime::new(max_worker_count~ : Int = 1024) -> Runtime raise {
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
  init_thread_pool_ffi(notify_send)
  {
    notify_recv,
    notify_send,
    max_worker_count,
    job_queue: @deque.new(),
    idle_workers: @deque.new(),
    running_workers: {},
  }
}

///|
extern "C" fn destroy_thread_pool() = "moonbitlang_async_destroy_thread_pool"

///|
pub fn Runtime::destroy(rt : Runtime) -> Unit {
  destroy_thread_pool()
  @fd_util.close(rt.notify_recv) catch {
    _ => ()
  }
  @fd_util.close(rt.notify_send) catch {
    _ => ()
  }
}

///|
#borrow(job_slot)
extern "C" fn spawn_worker(job_slot : Ref[Job]) -> Int64 = "moonbitlang_async_spawn_worker"

///|
extern "C" fn wake_worker(worker_id : Int64) = "moonbitlang_async_wake_worker"

///|
pub fn Runtime::submit_job(rt : Runtime, job : Job) -> Unit {
  match rt.idle_workers.pop_front() {
    None if rt.running_workers.size() > rt.max_worker_count =>
      rt.job_queue.push_back(job)
    None => {
      let job_slot = @ref.new(job)
      let id = spawn_worker(job_slot)
      rt.running_workers[job.id()] = { id, job_slot }
    }
    Some(worker) => {
      worker.job_slot.val = job
      rt.running_workers[job.id()] = worker
      wake_worker(worker.id)
    }
  }
}

///|
extern "C" fn fetch_completion_ffi(notify_recv : Int) -> Int = "moonbitlang_async_fetch_completion"

///|
pub fn Runtime::fetch_completion(rt : Runtime) -> Int? raise {
  let job_id = fetch_completion_ffi(rt.notify_recv)
  if job_id < 0 {
    if not(@os_error.is_nonblocking_io_error()) {
      @os_error.check_errno()
    }
    None
  } else {
    guard rt.running_workers.get(job_id) is Some(worker)
    rt.running_workers.remove(job_id)
    match rt.job_queue.pop_front() {
      None => rt.idle_workers.push_back(worker)
      Some(job) => {
        worker.job_slot.val = job
        wake_worker(worker.id)
      }
    }
    Some(job_id)
  }
}
