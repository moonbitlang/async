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
pub type Fd = @types.Fd

///|
fn close_ffi(fd : Fd) -> Int = "moonbit_v0" "fd_util/close_fd"

///|
pub fn close(fd : Fd, kind~ : FileKind, context~ : String) -> Unit raise {
  ignore(kind)
  if close_ffi(fd) < 0 {
    @os_error.check_errno(context)
  }
}

///|
pub let invalid_fd : Fd = -1

///|
pub fn fd_is_valid(fd : Fd) -> Bool {
  fd >= 0
}

///|
fn pipe_ffi(fds : Int, len : Int) -> Int = "moonbit_v0" "fd_util/pipe"

///|
#borrow(array)
fn int_array_to_ptr(array : FixedArray[Int]) -> Int =
  #|(func (param i32) (result i32) local.get 0)

///|
pub fn pipe(
  read_end_is_async~ : Bool,
  write_end_is_async~ : Bool,
  context~ : String,
) -> (Fd, Fd) raise {
  ignore(read_end_is_async)
  ignore(write_end_is_async)
  let fds = FixedArray::make(2, 0)
  if pipe_ffi(int_array_to_ptr(fds), fds.length()) < 0 {
    @os_error.check_errno(context)
  }
  (fds[0], fds[1])
}
