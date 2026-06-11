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
pub fn get_errno() -> Int = "moonbit_v0" "get_errno"

///|
fn errno_is_nonblocking_io_error(errno : Int) -> Bool = "moonbit_v0" "is_nonblocking_io_error"

///|
fn errno_is_EINTR(errno : Int) -> Bool = "moonbit_v0" "is_EINTR"

///|
fn errno_is_ENOENT(errno : Int) -> Bool = "moonbit_v0" "is_ENOENT"

///|
fn errno_is_EEXIST(errno : Int) -> Bool = "moonbit_v0" "is_EEXIST"

///|
fn errno_is_EACCES(errno : Int) -> Bool = "moonbit_v0" "is_EACCES"

///|
fn errno_is_ECONNREFUSED(errno : Int) -> Bool = "moonbit_v0" "is_ECONNREFUSED"

///|
fn errno_is_ERROR_NOTIFY_ENUM_DIR(errno : Int) -> Bool = "moonbit_v0" "is_ERROR_NOTIFY_ENUM_DIR"

///|
pub fn is_nonblocking_io_error() -> Bool {
  errno_is_nonblocking_io_error(get_errno())
}

///|
#internal(internal, "for internal use only")
pub fn errno_to_string(errno : Int) -> String {
  "errno \{errno}"
}

///|
pub(all) suberror OSError {
  OSError(Int, context~ : String)
} derive(ToJson)

///|
pub impl Show for OSError with fn output(self, logger) -> Unit {
  let OSError(errno, context~) = self
  let msg = "\{context}: \{errno_to_string(errno)}"
  logger <+ "OSError(\{to_repr(msg)})"
}

///|
pub fn OSError::is_nonblocking_io_error(err : OSError) -> Bool {
  let OSError(errno, ..) = err
  errno_is_nonblocking_io_error(errno)
}

///|
pub fn OSError::is_EINTR(err : OSError) -> Bool {
  let OSError(errno, ..) = err
  errno_is_EINTR(errno)
}

///|
pub fn OSError::is_ENOENT(err : OSError) -> Bool {
  let OSError(errno, ..) = err
  errno_is_ENOENT(errno)
}

///|
pub fn OSError::is_EEXIST(err : OSError) -> Bool {
  let OSError(errno, ..) = err
  errno_is_EEXIST(errno)
}

///|
pub fn OSError::is_EACCES(err : OSError) -> Bool {
  let OSError(errno, ..) = err
  errno_is_EACCES(errno)
}

///|
pub fn OSError::is_ECONNREFUSED(err : OSError) -> Bool {
  let OSError(errno, ..) = err
  errno_is_ECONNREFUSED(errno)
}

///|
pub fn OSError::is_ERROR_NOTIFY_ENUM_DIR(err : OSError) -> Bool {
  let OSError(errno, ..) = err
  errno_is_ERROR_NOTIFY_ENUM_DIR(errno)
}

///|
pub fn check_errno(context : String) -> Unit raise OSError {
  let err_code = get_errno()
  if err_code != 0 {
    raise OSError(err_code, context~)
  }
}

///|
fn get_ENOTDIR() -> Int = "moonbit_v0" "get_ENOTDIR"

///|
pub let errno_ENOTDIR : Int = get_ENOTDIR()
