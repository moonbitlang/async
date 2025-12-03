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
priv type Worker

///|
extern "C" fn init_thread_pool_ffi(notify_send : Int) = "moonbitlang_async_init_thread_pool"

///|
extern "C" fn destroy_thread_pool() = "moonbitlang_async_destroy_thread_pool"

///|
priv type JobData

///|
#external
priv type JobWorkerFunc

///|
#owned(init_job_data)
extern "C" fn spawn_worker(
  init_job_id : Int,
  init_job_data : JobData,
  init_job_worker : JobWorkerFunc,
) -> Worker = "moonbitlang_async_spawn_worker"

///|
#borrow(worker)
#owned(job_data)
extern "C" fn wake_worker(
  worker : Worker,
  job_id : Int,
  job_data : JobData,
  job_worker : JobWorkerFunc,
) = "moonbitlang_async_wake_worker"

///|
extern "C" fn fetch_completion_ffi(notify_recv : Int) -> Int = "moonbitlang_async_fetch_completion"
