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
pub extern "C" fn get_errno() -> Int = "moonbitlang_async_get_errno"

///|
extern "C" fn errno_is_nonblocking_io_error(errno : Int) -> Bool = "moonbitlang_async_is_nonblocking_io_error"

///|
pub fn is_nonblocking_io_error() -> Bool {
  errno_is_nonblocking_io_error(get_errno())
}

///|
pub(all) suberror OSError Int derive(Show)

///|
pub fn OSError::is_nonblocking_io_error(err : OSError) -> Bool {
  let OSError(errno) = err
  errno_is_nonblocking_io_error(errno)
}

///|
pub fn check_errno() -> Unit raise OSError {
  let err_code = get_errno()
  if err_code != 0 {
    raise OSError(err_code)
  }
}
