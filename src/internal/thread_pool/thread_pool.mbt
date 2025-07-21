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
pub fn init_thread_pool() -> Int raise {
  let completion_fd = init_thread_pool_ffi()
  if completion_fd < 0 {
    @os_error.check_errno()
  }
  completion_fd
}

///|
pub extern "C" fn destroy_thread_pool() = "moonbitlang_async_destroy_thread_pool"

///|
#external
type Job

///|
pub extern "C" fn Job::id(self : Job) -> Int = "moonbitlang_async_job_get_id"

///|
pub extern "C" fn Job::ret(self : Job) -> Int = "moonbitlang_async_job_get_ret"

///|
pub extern "C" fn Job::err(self : Job) -> Int = "moonbitlang_async_job_get_err"

///|
pub extern "C" fn submit_job(job : Job) = "moonbitlang_async_submit_job"

///|
pub extern "C" fn sleep_job(time : Int) -> Job = "moonbitlang_async_make_sleep_job"

///|
#borrow(buf)
pub extern "C" fn read_job(
  fd : Int,
  buf : FixedArray[Byte],
  offset : Int,
  len : Int,
) -> Job = "moonbitlang_async_make_read_job"

///|
#borrow(buf)
pub extern "C" fn write_job(
  fd : Int,
  buf : Bytes,
  offset : Int,
  len : Int,
) -> Job = "moonbitlang_async_make_write_job"

///|
#borrow(filename)
pub extern "C" fn open_job(filename : Bytes, flags : Int, mode : Int) -> Job = "moonbitlang_async_make_open_job"

///|
#borrow(path)
pub extern "C" fn remove_job(path : Bytes) -> Job = "moonbitlang_async_make_remove_job"

///|
extern "C" fn fetch_completion_ffi() -> Int = "moonbitlang_async_fetch_completion"

///|
pub fn fetch_completion() -> Int? raise {
  let job_id = fetch_completion_ffi()
  if job_id < 0 {
    if not(@os_error.is_nonblocking_io_error()) {
      @os_error.check_errno()
    }
    None
  } else {
    Some(job_id)
  }
}
