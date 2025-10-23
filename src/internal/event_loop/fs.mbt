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

/// Represents an open directory handle for reading directory entries.
/// 
/// This is an opaque external type that represents a directory opened for reading.
/// Use with `readdir` to iterate through directory contents.
///|
#external
pub type Directory

/// Represents an open directory handle for reading directory entries.
/// 
/// This is an opaque external type that represents a directory opened for reading.
/// Use with `readdir` to iterate through directory contents.
/// Represents a single directory entry returned by `readdir`.
/// 
/// This is an opaque external type that contains information about a file
/// or subdirectory within a directory. The actual contents are managed by
/// the underlying C implementation.
///|
#external
pub type DirectoryEntry

/// Opens a file asynchronously.
/// 
/// This function opens a file with the specified flags and mode.
/// The operation is performed in a worker thread to avoid blocking.
/// 
/// # Parameters
/// - `path`: Path to the file to open
/// - `flags`: Open flags (e.g., O_RDONLY, O_WRONLY, O_CREAT)
/// - `mode`: File permissions when creating new files
/// - `context`: Error context for debugging
/// 
/// # Returns
/// File descriptor of the opened file
/// 
/// # Errors
/// Raises OSError if the file cannot be opened
///|
pub async fn open(
  path : StringView,
  flags~ : Int,
  mode~ : Int,
  context~ : String,
) -> Int {
  let path = @encoding/utf8.encode(path)
  perform_job_in_worker(JobForWorker::open(path, flags, mode), context~)
}

/// File status information structure.
/// 
/// Contains metadata about a file such as size, permissions, timestamps, etc.
/// This is a wrapper around the system's stat structure.
///|
struct Stat(FixedArray[Byte])

///|
extern "C" fn sizeof_stat() -> Int = "moonbitlang_async_sizeof_stat"

/// Creates a new Stat structure initialized with zeros.
/// 
/// # Returns
/// A new Stat instance ready to be filled by `stat` function
///|
pub fn Stat::new() -> Stat {
  FixedArray::make(sizeof_stat(), b'\x00')
}

/// Gets file status information asynchronously.
/// 
/// # Parameters
/// - `path`: Path to the file
/// - `follow_symlink`: Whether to follow symbolic links
/// - `context`: Error context for debugging
/// 
/// # Returns
/// Stat structure containing file information
///|
pub async fn stat(
  path : StringView,
  follow_symlink~ : Bool,
  context~ : String,
) -> Stat {
  let path = @encoding/utf8.encode(path)
  let stat = Stat::new()
  let _ = perform_job_in_worker(
    JobForWorker::stat(path, stat, follow_symlink~),
    context~,
  )
  stat
}

/// Tests file accessibility asynchronously.
/// 
/// # Parameters
/// - `path`: Path to test
/// - `amode`: Access mode to test (F_OK, R_OK, W_OK, X_OK)
/// - `context`: Error context for debugging
/// 
/// # Returns
/// 0 if accessible, -1 otherwise
///|
pub async fn access(path : StringView, amode~ : Int, context~ : String) -> Int {
  let path = @encoding/utf8.encode(path)
  perform_job_in_worker(JobForWorker::access(path, amode), context~)
}

/// Synchronizes file data to disk asynchronously.
/// 
/// # Parameters
/// - `fd`: File descriptor to sync
/// - `only_data`: If true, sync only data; if false, sync data and metadata
/// - `context`: Error context for debugging
///|
pub async fn fsync(fd : Int, only_data~ : Bool, context~ : String) -> Unit {
  perform_job_in_worker(JobForWorker::fsync(fd, only_data), context~) |> ignore
}

/// Removes a file asynchronously.
/// 
/// # Parameters
/// - `path`: Path to the file to remove
/// - `context`: Error context for debugging
///|
pub async fn remove(path : StringView, context~ : String) -> Unit {
  let path = @encoding/utf8.encode(path)
  perform_job_in_worker(JobForWorker::remove(path), context~) |> ignore
}

/// Creates a directory asynchronously.
/// 
/// # Parameters
/// - `path`: Path of the directory to create
/// - `mode`: Directory permissions
/// - `context`: Error context for debugging
///|
pub async fn mkdir(path : StringView, mode~ : Int, context~ : String) -> Unit {
  let path = @encoding/utf8.encode(path)
  perform_job_in_worker(JobForWorker::mkdir(path, mode), context~) |> ignore
}

/// Removes an empty directory asynchronously.
/// 
/// # Parameters
/// - `path`: Path of the directory to remove
/// - `context`: Error context for debugging
///|
pub async fn rmdir(path : StringView, context~ : String) -> Unit {
  let path = @encoding/utf8.encode(path)
  perform_job_in_worker(JobForWorker::rmdir(path), context~) |> ignore
}

///|
extern "C" fn DirectoryEntry::null() -> DirectoryEntry = "moonbitlang_async_null_dirent"

/// Reads the next directory entry asynchronously.
/// 
/// # Parameters
/// - `dir`: Directory handle to read from
/// - `context`: Error context for debugging
/// 
/// # Returns
/// Next directory entry, or null entry if at end
///|
pub async fn readdir(dir : Directory, context~ : String) -> DirectoryEntry {
  let out = @ref.new(DirectoryEntry::null())
  let _ = perform_job_in_worker(JobForWorker::readdir(dir, out), context~)
  out.val
}

/// Resolves a pathname to its canonical absolute form asynchronously.
/// 
/// # Parameters
/// - `path`: Path to resolve
/// - `context`: Error context for debugging
/// 
/// # Returns
/// Canonical absolute path as bytes
///|
pub async fn realpath(path : StringView, context~ : String) -> Bytes {
  let path = @encoding/utf8.encode(path)
  let out = @ref.new(@c_buffer.null)
  let _ = perform_job_in_worker(JobForWorker::realpath(path, out), context~)
  let c_path = out.val
  defer c_path.free()
  let len = c_path.strlen()
  let result = FixedArray::make(len, b'\x00')
  c_path.blit_to_bytes(dst=result, offset=0, len~)
  result.unsafe_reinterpret_as_bytes()
}
