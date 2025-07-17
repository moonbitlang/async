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
extern "C" fn init_thread_pool_ffi() -> Int = "moonbitlang_async_init_thread_pool"

///|
fn init_thread_pool() -> Int raise {
  let completion_fd = init_thread_pool_ffi()
  if completion_fd < 0 {
    @os_error.check_errno()
  }
  completion_fd
}

///|
extern "C" fn destroy_thread_pool() = "moonbitlang_async_destroy_thread_pool"

///|
#external
type Job

///|
extern "C" fn submit_job(job : Job) -> Int = "moonbitlang_async_submit_job"

///|
pub extern "C" fn make_sleep_job(time : Int) -> Job = "moonbitlang_async_make_sleep_job"

///|
#borrow(buf)
pub extern "C" fn make_read_job(
  fd : Int,
  buf : FixedArray[Byte],
  len : Int
) -> Job = "moonbitlang_async_make_read_job"

///|
#borrow(buf)
pub extern "C" fn make_write_job(fd : Int, buf : Bytes, len : Int) -> Job = "moonbitlang_async_make_write_job"

///|
#borrow(filename)
pub extern "C" fn make_open_job(filename : Bytes, flags : Int) -> Job = "moonbitlang_async_make_open_job"

///|
priv struct JobResult {
  job_id : Int
  ret : Int
  err : Int
}

///|
#borrow(result)
extern "C" fn fetch_completion_ffi(result : JobResult) -> Int = "moonbitlang_async_fetch_completion"

///|
fn fetch_completion() -> JobResult? raise {
  let result = { job_id: -1, ret: 0, err: 0 }
  if fetch_completion_ffi(result) < 0 {
    if not(@os_error.is_nonblocking_io_error()) {
      @os_error.check_errno()
    }
    None
  } else {
    Some(result)
  }
}
