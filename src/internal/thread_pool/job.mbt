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
#external
type Job

///|
pub extern "C" fn Job::id(self : Job) -> Int = "moonbitlang_async_job_get_id"

///|
pub extern "C" fn Job::ret(self : Job) -> Int = "moonbitlang_async_job_get_ret"

///|
pub extern "C" fn Job::err(self : Job) -> Int = "moonbitlang_async_job_get_err"

///|
pub extern "C" fn sleep_job(time : Int) -> Job = "moonbitlang_async_make_sleep_job"

///|
pub extern "C" fn Job::read(
  fd : Int,
  buf : FixedArray[Byte],
  offset : Int,
  len : Int,
) -> Job = "moonbitlang_async_make_read_job"

///|
pub extern "C" fn Job::write(
  fd : Int,
  buf : Bytes,
  offset : Int,
  len : Int,
) -> Job = "moonbitlang_async_make_write_job"

///|
pub extern "C" fn Job::open(filename : Bytes, flags : Int, mode : Int) -> Job = "moonbitlang_async_make_open_job"

///|
pub extern "C" fn Job::remove(path : Bytes) -> Job = "moonbitlang_async_make_remove_job"

///|
pub extern "C" fn Job::spawn(
  path : Bytes,
  args : FixedArray[Bytes?],
  env : FixedArray[Bytes?],
  stdin : Int,
  stdout : Int,
  stderr : Int,
) -> Job = "moonbitlang_async_make_spawn_job"
