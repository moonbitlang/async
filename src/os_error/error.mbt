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
/// An error from the operating system.
///
/// The positional parameter of type `Kind` is a platform-independent abstraction
/// for common kinds of error, such as file not found.
/// It can be used to match against special error in a portable way.
/// Note that not all error has a corresponding `Kind`.
///
/// `raw_code` is the raw, system-specific error number.
/// `context` describe the context that generated this error.
pub suberror OsError {
  OsError(Kind, raw_code~ : Int, context~ : String)
} derive(ToJson)

///|
/// Create a `OsError` from a raw error number
#as_free_fn
pub fn OsError::from_errno(errno : Int, context~ : String) -> OsError {
  OsError(Kind(errno), raw_code=errno, context~)
}

///|
/// Transform the context of a `OsError` using `f`
pub fn OsError::wrap_context(err : OsError, f : (String) -> String) -> OsError {
  let OsError(kind, raw_code~, context~) = err
  OsError(kind, raw_code~, context=f(context))
}

///|
pub impl Show for OsError with fn output(self, logger) -> Unit {
  let OsError(_, raw_code~, context~) = self
  logger
  ..write_string(context)
  ..write_string(": ")
  .write_string(errno_to_string(raw_code))
}

///|
pub impl Debug for OsError with fn to_repr(self) {
  Repr::opaque_("@os_error.OSError", Repr::string(self.to_string()))
}

///|
pub fn OsError::is_nonblocking_io_error(err : OsError) -> Bool {
  let OsError(_, raw_code~, ..) = err
  errno_is_nonblocking_io_error(raw_code)
}

///|
pub fn OsError::is_EINTR(err : OsError) -> Bool {
  let OsError(_, raw_code~, ..) = err
  match @env_util.platform {
    Linux => raw_code == linux_EINTR
    MacOS => raw_code == macos_EINTR
    Windows => false
  }
}

///|
pub extend OsError with Show::{to_string}

///|
/// Detect whether the error is the Windows `ERROR_NOTIFY_ENUM_DIR` error.
pub fn OsError::is_ERROR_NOTIFY_ENUM_DIR(err : OsError) -> Bool {
  let OsError(_, raw_code~, ..) = err
  match @env_util.platform {
    Linux | MacOS => false
    Windows => raw_code == windows_ERROR_NOTIFY_ENUM_DIR
  }
}

///|
pub fn check_errno(context : String) -> Unit raise OsError {
  let err_code = get_errno()
  if err_code != 0 {
    raise OsError(Kind(err_code), raw_code=err_code, context~)
  }
}

///|
pub let errno_ENOTDIR : Int = match @env_util.platform {
  Linux => linux_ENOTDIR
  MacOS => macos_ENOTDIR
  Windows => windows_ERROR_DIRECTORY
}

///|
pub let errno_ENOTSUP : Int = match @env_util.platform {
  Linux => linux_ENOTSUP
  MacOS => macos_ENOTSUP
  Windows => windows_ERROR_NOT_SUPPORTED
}
