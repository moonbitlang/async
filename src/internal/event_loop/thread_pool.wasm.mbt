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
priv struct Worker(Int)

///|
fn init_thread_pool_ffi() -> Unit {
  ()
}

///|
fn destroy_thread_pool() -> Unit {
  ()
}

///|
fn spawn_worker_ffi(init_job_id : Int, init_job : Int) -> Int = "moonbit_v0" "thread_pool/spawn_worker"

///|
fn free_worker_ffi(worker : Int) -> Unit = "moonbit_v0" "thread_pool/free_worker"

///|
fn wake_worker_ffi(worker : Int, job_id : Int, job : Int) -> Unit = "moonbit_v0" "thread_pool/wake_worker"

///|
fn worker_enter_idle_ffi(worker : Int) -> Unit = "moonbit_v0" "thread_pool/worker_enter_idle"

///|
fn cancel_worker_ffi(worker : Int) -> Int = "moonbit_v0" "thread_pool/cancel_worker"

///|
fn fetch_completion_raw(output : Int, len : Int) -> Int = "moonbit_v0" "thread_pool/fetch_completion"

///|
#borrow(array)
fn int_array_to_ptr(array : FixedArray[Int]) -> Int =
  #|(func (param i32) (result i32) local.get 0)

///|
fn fetch_completion_ffi(output : FixedArray[Int]) -> Int {
  fetch_completion_raw(int_array_to_ptr(output), output.length())
}

///|
fn Worker::spawn(init_job_id : Int, init_job : Job) -> Worker {
  Worker(spawn_worker_ffi(init_job_id, init_job.handle))
}

///|
fn Worker::free(worker : Worker) -> Unit {
  free_worker_ffi(worker.0)
}

///|
fn Worker::wake(worker : Worker, job_id : Int, job : Job) -> Unit {
  wake_worker_ffi(worker.0, job_id, job.handle)
}

///|
fn Worker::enter_idle(worker : Worker) -> Unit {
  worker_enter_idle_ffi(worker.0)
}

///|
fn Worker::cancel_ffi(worker : Worker) -> Int {
  cancel_worker_ffi(worker.0)
}

///|
fn Worker::cancel(
  worker : Worker,
  context~ : String,
) -> CancellationStatus raise {
  match worker.cancel_ffi() {
    // The wasm host cannot interrupt every blocking OS operation yet. It still
    // drains the worker completion later, but cancellation should resume the
    // coroutine immediately to match the async timeout surface.
    0 => NoWait
    1 => NeedWait
    2 => RetryLater
    _ => {
      @os_error.check_errno(context)
      NoWait
    }
  }
}

///|
priv struct Job {
  handle : Int
}

///|
fn free_job_ffi(job : Int) -> Unit = "moonbit_v0" "thread_pool/free_job"

///|
fn run_job_ffi(job : Int) -> Unit = "moonbit_v0" "thread_pool/run_job"

///|
fn job_get_ret_ffi(job : Int) -> Int = "moonbit_v0" "thread_pool/job_get_ret"

///|
fn job_get_err_ffi(job : Int) -> Int = "moonbit_v0" "thread_pool/job_get_err"

///|
fn Job::free(self : Job) -> Unit {
  free_job_ffi(self.handle)
}

///|
fn Job::run(self : Job) -> Unit {
  run_job_ffi(self.handle)
}

///|
fn Job::ret(self : Job) -> Int {
  job_get_ret_ffi(self.handle)
}

///|
fn Job::err(self : Job) -> Int {
  job_get_err_ffi(self.handle)
}
