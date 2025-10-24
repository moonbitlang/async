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
extern "C" fn fd_is_nonblocking_ffi(fd : Int) -> Int = "moonbitlang_async_fd_is_nonblocking"

///|
pub fn fd_is_nonblocking(fd : Int, context~ : String) -> Bool raise {
  let ret = fd_is_nonblocking_ffi(fd)
  if ret < 0 {
    @os_error.check_errno(context)
  }
  ret > 0
}

///|
extern "C" fn set_blocking_ffi(fd : Int) -> Int = "moonbitlang_async_set_blocking"

///|
pub fn set_blocking(fd : Int, context~ : String) -> Unit raise {
  if set_blocking_ffi(fd) < 0 {
    @os_error.check_errno(context)
  }
}

///|
extern "C" fn set_nonblocking_ffi(fd : Int) -> Int = "moonbitlang_async_set_nonblocking"

///|
pub fn set_nonblocking(fd : Int, context~ : String) -> Unit raise {
  if set_nonblocking_ffi(fd) < 0 {
    @os_error.check_errno(context)
  }
}

///|
extern "C" fn set_cloexec_ffi(fd : Int) -> Int = "moonbitlang_async_set_cloexec"

///|
pub fn set_cloexec(fd : Int, context~ : String) -> Unit raise {
  if set_cloexec_ffi(fd) < 0 {
    @os_error.check_errno(context)
  }
}

///|
#borrow(fds)
extern "C" fn pipe_ffi(fds : FixedArray[Int]) -> Int = "moonbitlang_async_pipe"

///|
pub fn pipe(context : String) -> (Int, Int) raise {
  let fds : FixedArray[Int] = [0, 0]
  if 0 != pipe_ffi(fds) {
    @os_error.check_errno(context)
  }
  guard fds is [r, w]
  set_cloexec(r, context~)
  set_cloexec(w, context~)
  (r, w)
}

///|
extern "C" fn close_ffi(fd : Int) -> Int = "close"

///|
pub fn close(fd : Int, context~ : String) -> Unit raise {
  if close_ffi(fd) < 0 {
    @os_error.check_errno(context)
  }
}
