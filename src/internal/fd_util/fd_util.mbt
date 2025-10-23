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

/// FFI function to set a file descriptor to blocking mode
extern "C" fn set_blocking_ffi(fd : Int) -> Int = "moonbitlang_async_set_blocking"

/// Sets a file descriptor to blocking I/O mode.
/// 
/// This function configures the specified file descriptor to operate in blocking mode,
/// where I/O operations will block the calling thread until completion.
///
/// # Parameters
/// - `fd`: The file descriptor to configure
/// - `context`: Error context for debugging purposes
///
/// # Errors
/// Raises an error if the system call fails
///
/// # Example
/// ```moonbit
/// let result = pipe("create pipe for blocking test")
/// let read_fd = result.0
/// set_blocking(read_fd, context="setting to blocking mode")
/// close(read_fd, context="cleanup")
/// close(result.1, context="cleanup")
/// ```
pub fn set_blocking(fd : Int, context~ : String) -> Unit raise {
  if set_blocking_ffi(fd) < 0 {
    @os_error.check_errno(context)
  }
}

/// FFI function to set a file descriptor to non-blocking mode
extern "C" fn set_nonblocking_ffi(fd : Int) -> Int = "moonbitlang_async_set_nonblocking"

/// Sets a file descriptor to non-blocking I/O mode.
/// 
/// This function configures the specified file descriptor to operate in non-blocking mode,
/// where I/O operations will return immediately even if no data is available.
///
/// # Parameters
/// - `fd`: The file descriptor to configure
/// - `context`: Error context for debugging purposes
///
/// # Errors
/// Raises an error if the system call fails
///
/// # Example
/// ```moonbit
/// let result = pipe("create pipe for non-blocking test")
/// let read_fd = result.0
/// set_nonblocking(read_fd, context="setting to non-blocking mode")
/// close(read_fd, context="cleanup")
/// close(result.1, context="cleanup")
/// ```
pub fn set_nonblocking(fd : Int, context~ : String) -> Unit raise {
  if set_nonblocking_ffi(fd) < 0 {
    @os_error.check_errno(context)
  }
}

/// FFI function to set the close-on-exec flag for a file descriptor
extern "C" fn set_cloexec_ffi(fd : Int) -> Int = "moonbitlang_async_set_cloexec"

/// Sets the close-on-exec flag for a file descriptor.
/// 
/// This function sets the FD_CLOEXEC flag on the specified file descriptor,
/// ensuring that it will be automatically closed when a new program is executed
/// via exec() family functions.
///
/// # Parameters
/// - `fd`: The file descriptor to configure
/// - `context`: Error context for debugging purposes
///
/// # Errors
/// Raises an error if the system call fails
///
/// # Example
/// ```moonbit
/// let result = pipe("create pipe for cloexec test")
/// let test_fd = result.0
/// set_cloexec(test_fd, context="setting close-on-exec flag")
/// close(test_fd, context="cleanup")
/// close(result.1, context="cleanup")
/// ```
pub fn set_cloexec(fd : Int, context~ : String) -> Unit raise {
  if set_cloexec_ffi(fd) < 0 {
    @os_error.check_errno(context)
  }
}

/// FFI function to create a pipe
#borrow(fds)
extern "C" fn pipe_ffi(fds : FixedArray[Int]) -> Int = "moonbitlang_async_pipe"

/// Creates a pipe and returns file descriptors for reading and writing.
/// 
/// This function creates a unidirectional data channel (pipe) that can be used
/// for inter-process communication. It returns a tuple containing the read-end
/// and write-end file descriptors. Both file descriptors are automatically
/// configured with the close-on-exec flag.
///
/// # Parameters
/// - `context`: Error context for debugging purposes
///
/// # Returns
/// A tuple `(read_fd, write_fd)` where:
/// - `read_fd`: File descriptor for reading from the pipe
/// - `write_fd`: File descriptor for writing to the pipe
///
/// # Errors
/// Raises an error if pipe creation fails
///
/// # Example
/// ```moonbit
/// let result = pipe("creating communication pipe")
/// let read_fd = result.0
/// let write_fd = result.1
/// // Use file descriptors for communication
/// close(read_fd, context="cleanup read end")
/// close(write_fd, context="cleanup write end")
/// ```
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

/// FFI function to close a file descriptor
extern "C" fn close_ffi(fd : Int) -> Int = "close"

/// Closes a file descriptor.
/// 
/// This function closes the specified file descriptor, releasing any associated
/// system resources. After closing, the file descriptor should not be used again.
///
/// # Parameters
/// - `fd`: The file descriptor to close
/// - `context`: Error context for debugging purposes
///
/// # Errors
/// Raises an error if the close operation fails
///
/// # Example
/// ```moonbit
/// let result = pipe("create pipe for close test")
/// let test_fd = result.0
/// close(test_fd, context="closing file descriptor")
/// close(result.1, context="cleanup")
/// ```
pub fn close(fd : Int, context~ : String) -> Unit raise {
  if close_ffi(fd) < 0 {
    @os_error.check_errno(context)
  }
}
