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
pub let not_directory : Int = match @env_util.platform {
  Linux => linux_ENOTDIR
  MacOS => macos_ENOTDIR
  Windows => windows_ERROR_DIRECTORY
}

///|
pub let not_supported : Int = match @env_util.platform {
  Linux => linux_ENOTSUP
  MacOS => macos_ENOTSUP
  Windows => windows_ERROR_NOT_SUPPORTED
}

///|
pub let operation_aborted : Int = match @env_util.platform {
  Linux => linux_EINTR
  MacOS => macos_EINTR
  Windows => windows_ERROR_OPERATION_ABORTED
}

///|
pub let lock_violation : Int = match @env_util.platform {
  Linux => linux_EWOULDBLOCK
  MacOS => macos_EWOULDBLOCK
  Windows => windows_ERROR_LOCK_VIOLATION
}

///|
#cfg(target="native")
pub extern "C" fn get_errno() -> Int = "moonbitlang_async_get_errno"

///|
#cfg(target="wasm")
#unsafe_skip_stub_check
pub fn get_errno() -> Int = "moonbitlang/async" "os_error/get_errno"

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
pub fn errno_is_nonblocking_io_error(errno : Int) -> Bool {
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
