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
#cfg(target="native")
pub extern "C" fn get_errno() -> Int = "moonbitlang_async_get_errno"

///|
#cfg(target="wasm")
#unsafe_skip_stub_check
pub fn get_errno() -> Int = "moonbitlang/async" "os_error/get_errno"

///|
fn errno_is_nonblocking_io_error(errno : Int) -> Bool {
  match @env_util.platform {
    Linux =>
      errno == linux_EAGAIN ||
      errno == linux_EINPROGRESS ||
      errno == linux_EWOULDBLOCK
    MacOS =>
      errno == macos_EAGAIN ||
      errno == macos_EINPROGRESS ||
      errno == macos_EWOULDBLOCK
    Windows =>
      errno == windows_ERROR_IO_INCOMPLETE || errno == windows_ERROR_IO_PENDING
  }
}

///|
pub fn is_nonblocking_io_error() -> Bool {
  errno_is_nonblocking_io_error(get_errno())
}

///|
#cfg(target="native")
extern "C" fn strerror(errno : Int) -> @c_buffer.Buffer = "moonbitlang_async_errno_to_string"

///|
#unsafe_skip_stub_check
#cfg(target="wasm")
fn strerror(errno : Int) -> @c_buffer.Buffer = "moonbitlang/async" "os_error/errno_to_string"

///|
#cfg(target="native")
extern "C" fn free_errno_str(str : @c_buffer.Buffer) = "moonbitlang_async_free_errno_str"

///|
#unsafe_skip_stub_check
#cfg(target="wasm")
#owned(str)
fn free_errno_str(str : @c_buffer.Buffer) -> Unit = "moonbitlang/async" "os_error/free_errno_str"

///|
#internal(internal, "for internal use only")
pub fn errno_to_string(errno : Int) -> String {
  let c_str = strerror(errno)
  defer free_errno_str(c_str)
  @os_string.decode(c_str).trim_end(chars="\r\n").to_owned()
}

///|
pub(all) suberror OSError {
  OSError(Int, context~ : String)
} derive(ToJson)

///|
pub impl Show for OSError with fn output(self, logger) -> Unit {
  let OSError(errno, context~) = self
  let msg = "\{context}: \{errno_to_string(errno)}"
  logger <+ "OSError(\{Repr(msg)})"
}

///|
pub impl Debug for OSError with fn to_repr(self) {
  let OSError(errno, context~) = self
  Repr::opaque_(
    "@os_error.OSError",
    Repr::string("\{context}: \{errno_to_string(errno)}"),
  )
}

///|
pub fn OSError::is_nonblocking_io_error(err : OSError) -> Bool {
  let OSError(errno, ..) = err
  errno_is_nonblocking_io_error(errno)
}

///|
pub fn OSError::is_EINTR(err : OSError) -> Bool {
  let OSError(errno, ..) = err
  match @env_util.platform {
    Linux => errno == linux_EINTR
    MacOS => errno == macos_EINTR
    Windows => false
  }
}

///|
/// Detect whether the error is the `ENOENT` (no such file or directory) error.
pub fn OSError::is_ENOENT(err : OSError) -> Bool {
  let OSError(errno, ..) = err
  match @env_util.platform {
    Linux => errno == linux_ENOENT
    MacOS => errno == macos_ENOENT
    Windows =>
      errno == windows_ERROR_FILE_NOT_FOUND ||
      errno == windows_ERROR_PATH_NOT_FOUND
  }
}

///|
/// Detect whether the error is the `EEXIST` (already exists) error.
pub fn OSError::is_EEXIST(err : OSError) -> Bool {
  let OSError(errno, ..) = err
  match @env_util.platform {
    Linux => errno == linux_EEXIST
    MacOS => errno == macos_EEXIST
    Windows =>
      errno == windows_ERROR_FILE_EXISTS ||
      errno == windows_ERROR_ALREADY_EXISTS
  }
}

///|
/// Detect whether the error is the `EACCES` (permission denied) error.
pub fn OSError::is_EACCES(err : OSError) -> Bool {
  let OSError(errno, ..) = err
  match @env_util.platform {
    Linux => errno == linux_EACCES
    MacOS => errno == macos_EACCES
    Windows => errno == windows_ERROR_ACCESS_DENIED
  }
}

///|
/// Detect whether the error is the `ECONNREFUSED` (connection refused) error.
pub fn OSError::is_ECONNREFUSED(err : OSError) -> Bool {
  let OSError(errno, ..) = err
  match @env_util.platform {
    Linux => errno == linux_ECONNREFUSED
    MacOS => errno == macos_ECONNREFUSED
    Windows => errno == windows_ERROR_CONNECTION_REFUSED
  }
}

///|
/// Detect whether the error is the Windows `ERROR_NOTIFY_ENUM_DIR` error.
pub fn OSError::is_ERROR_NOTIFY_ENUM_DIR(err : OSError) -> Bool {
  let OSError(errno, ..) = err
  match @env_util.platform {
    Linux | MacOS => false
    Windows => errno == windows_ERROR_NOTIFY_ENUM_DIR
  }
}

///|
pub fn check_errno(context : String) -> Unit raise OSError {
  let err_code = get_errno()
  if err_code != 0 {
    raise OSError(err_code, context~)
  }
}

///|
pub let errno_ENOTDIR : Int = match @env_util.platform {
  Linux => linux_ENOTDIR
  MacOS => macos_ENOTDIR
  Windows => windows_ERROR_DIRECTORY
}

///|
pub fn OSError::is_ENOTDIR(err : OSError) -> Bool {
  let OSError(errno, ..) = err
  errno == errno_ENOTDIR
}

///|
pub let errno_ENOTSUP : Int = match @env_util.platform {
  Linux => linux_ENOTSUP
  MacOS => macos_ENOTSUP
  Windows => windows_ERROR_NOT_SUPPORTED
}

///|
pub let errno_EPIPE : Int = match @env_util.platform {
  Linux => linux_EPIPE
  MacOS => macos_EPIPE
  Windows => windows_ERROR_BROKEN_PIPE
}
