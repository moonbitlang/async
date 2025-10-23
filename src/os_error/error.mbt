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

/// Get the current errno value from the system.
/// This function returns the error code set by the last system call.
/// 
/// # Returns
/// 
/// The errno value as an Int, where 0 indicates no error.
/// 
/// # Examples
/// 
/// ```moonbit
/// let errno : Int = get_errno()
/// if errno != 0 {
///   // Handle error
/// }
/// ```
pub extern "C" fn get_errno() -> Int = "moonbitlang_async_get_errno"

extern "C" fn errno_is_nonblocking_io_error(errno : Int) -> Bool = "moonbitlang_async_is_nonblocking_io_error"

/// Check if the current errno indicates a non-blocking I/O error.
/// This function is useful for determining if an I/O operation failed because
/// it would block in non-blocking mode.
/// 
/// # Returns
/// 
/// `true` if the current errno indicates a non-blocking I/O error (such as EAGAIN or EWOULDBLOCK), `false` otherwise.
/// 
/// # Examples
/// 
/// ```moonbit
/// if is_nonblocking_io_error() {
///   // Retry the operation later
/// }
/// ```
pub fn is_nonblocking_io_error() -> Bool {
  errno_is_nonblocking_io_error(get_errno())
}

extern "C" fn strerror(errno : Int) -> @c_buffer.Buffer = "moonbitlang_async_errno_to_string"

/// OS error type that represents system-level errors.
/// This error type wraps an errno value along with contextual information
/// about where the error occurred.
/// 
/// # Fields
/// 
/// - `errno`: The system errno value
/// - `context`: A string describing the context where the error occurred
pub(all) suberror OSError {
  OSError(Int, context~ : String)
}

/// Implementation of the Show trait for OSError.
/// This provides a human-readable representation of OS errors by combining
/// the context with the system error message.
pub impl Show for OSError with output(self, logger) -> Unit {
  let OSError(errno, context~) = self
  let c_str = strerror(errno)
  let len = c_str.strlen()
  let data = FixedArray::make(len, (0 : Byte))
  c_str.blit_to_bytes(dst=data, offset=0, len~)
  let errno_desc = @encoding/utf8.decode_lossy(
    data.unsafe_reinterpret_as_bytes(),
  )
  logger
  ..write_string("OSError(")
  ..write_object("\{context}: \{errno_desc}")
  ..write_string(")")
}

/// Check if an OSError represents a non-blocking I/O error.
/// This method is useful for determining if an I/O operation failed because
/// it would block in non-blocking mode.
/// 
/// # Parameters
/// 
/// - `err`: The OSError to check
/// 
/// # Returns
/// 
/// `true` if the error indicates a non-blocking I/O error, `false` otherwise.
pub fn OSError::is_nonblocking_io_error(err : OSError) -> Bool {
  let OSError(errno, ..) = err
  errno_is_nonblocking_io_error(errno)
}

/// Check the current errno and raise an OSError if it indicates an error.
/// This function is typically called after system calls to handle errors.
/// 
/// # Parameters
/// 
/// - `context`: A string describing the operation that might have failed
/// 
/// # Raises
/// 
/// `OSError` if the current errno is non-zero
pub fn check_errno(context : String) -> Unit raise OSError {
  let err_code = get_errno()
  if err_code != 0 {
    raise OSError(err_code, context~)
  }
}
