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
struct File {
  io : @event_loop.IoHandle
  read_buf : @io.ReaderBuffer
}

///|
pub fn File::fd(self : File) -> @fd_util.Fd {
  self.io.fd()
}

///|
pub fn File::close(self : File) -> Unit {
  self.io.close()
}

///|
pub(all) enum Mode {
  ReadOnly = 0
  WriteOnly
  ReadWrite
}

///|
/// Determine how data is synchronized after writing:
///
/// - `NoSync` means no synchronization is performed.
///
/// - `Data` means the data part and relevant metadata such as file size
///   will be synchronized immediately after a `write` call,
///   but other metadata, such as last access time, will not.
///   See man page of `fdatasync(2)` for more details.
///
/// - `Full` means all data and metdata will be synchronized
///   immediately after writing.
///   See man page of `fsync(2)` for more details.
pub(all) enum SyncMode {
  NoSync
  Data
  Full
}

///|
/// Specify how to handle file creation in `@fs.open()`.
///
/// - `OpenExisting`: open an existing file, fail if the file does not exist
/// - `TruncateExisting`: open an existing file and truncate it, fail if the file does not exist
/// - `OpenOrCreate`: if the file exists, open it without truncation. Otherwise create a new file
/// - `CreateOrTruncate`: if the file exists, open it and truncate it. Otherwise create a new file
/// - `CreateNew`: create a new file, fail if the file already exists
pub(all) enum CreateMode {
  /// open an existing file, fail if the file does not exist
  OpenExisting = 0
  /// open an existing file and truncate it, fail if the file does not exist
  TruncateExisting = 1
  /// if the file exists, open it without truncation. Otherwise create a new file
  OpenOrCreate = 2
  /// if the file exists, open it and truncate it. Otherwise create a new file
  CreateOrTruncate = 3
  /// create a new file, fail if the file already exists
  CreateNew = 4
}

///|
fn CreateMode::to_int(self : CreateMode) -> Int = "%identity"

///|
/// Open a file. `filename` will be encoded using UTF8.
///
/// - `mode` determines what operations (read/write) are permitted for the file.
///
/// - `sync` determines how data will be synchronized to disk after writing,
///   see `SyncMode` for more details. The default is `NoSync`
///
/// - if `append` is `true` (`false` by default), the file will be opened in append mode.
///   Under append mode, sequential write (via the `@io.Writer` interface)
///   will always write to the end of the file, even if the file is modified externally.
///   The semantic of reading from the file is unaffected by `append`.
///   Random access write (`write_at`) is forbidden for file opened in append mode.
///
/// - `create_mode` specify how to handle file creation, truncation, etc.
///   See the type `CreateMode` for more details.
///   The default value is `OpenExisting`.
///
/// - `permission` specifies the user permission of the new file,
///   if a new file is created by `@fs.open`.
///   The permission is represented as an integer in UNIX permission style.
///   For example, `0o640` means:
///
///   - the owner of the file can read and write the file (`6`)
///   - users in the owner group of the file can read the file (`4`)
///   - other users can do nothing to the file
///
///   The default value is `0o644` (anyone can read, only owner can write, not executable).
///   `permission` is currently ignored on Windows.
#label_migration(create, fill=false, msg="the option `create` is deprecated, use `create_mode` and `permission` instead")
#label_migration(truncate, fill=false, msg="the option `truncate` is deprecated, use `create_mode` instead")
pub async fn open(
  filename : StringView,
  mode~ : Mode,
  sync? : SyncMode = NoSync,
  append? : Bool = false,
  create_mode? : CreateMode,
  permission? : Int,
  create? : Int,
  truncate? : Bool = false,
) -> File {
  let access = match mode {
    ReadOnly => 0
    WriteOnly => 1
    ReadWrite => 2
  }
  let create_mode = match create_mode {
    Some(mode) => mode
    None =>
      match (create is Some(_), truncate) {
        (true, true) => CreateOrTruncate
        (true, false) => OpenOrCreate
        (false, true) => TruncateExisting
        (false, false) => OpenExisting
      }
  }
  let permission = match permission {
    Some(perm) => perm
    None if create is Some(perm) => perm
    None => 0o644
  }
  let sync = match sync {
    NoSync => 0
    Data => 1
    Full => 2
  }
  let (io, _) = @event_loop.open(
    filename,
    access,
    create=create_mode.to_int(),
    append~,
    sync~,
    mode=permission,
    context="@fs.open()",
  )
  { io, read_buf: @io.ReaderBuffer::new() }
}

///|
/// Create a new file at `pathname`. `pathname` will be encoded using UTF8.
///
/// - If the file already exists and `allow_existing` is `true` (`true` by default),
///   the existing file will be truncated and opened.
///   If the file already exists and `allow_existing` is `fale`, this function will fail.
///
/// - User permission of the new file would be set to `permission`,
///   which is an integer in UNIX style. For example, `0o640` means:
///     - the owner of the file can read and write the file (`6`)
///     - users in the owner group of the file can read the file (`4`)
///     - other users can do nothing to the file
///   The default value is `0o644` (anyone can read, only owner can write, not executable).
///   `permission` is currently ignored on Windows.
///
/// - `sync` determines how data will be synchronized to disk after writing,
///   see `SyncMode` for more details. The default is `NoSync`
pub async fn create(
  filename : StringView,
  allow_existing? : Bool = true,
  permission? : Int = 0o644,
  sync? : SyncMode = NoSync,
) -> File {
  let create_mode = if allow_existing { CreateOrTruncate } else { CreateNew }
  open(filename, mode=WriteOnly, sync~, create_mode~, permission~)
}

///|
/// `file.read(buf, offset~, len~) read `len` bytes from `file`,
/// store data into `buf`, starting with `offset`.
/// By default, `offset` is `0` and `len` is `buf.length() - offset`.
///
/// The number of data actually read will be returned.
/// The number can be smaller than the requested size for various reasons:
///
/// - EOF is reached before reading all requested data
/// - the file is a named pipe, and not enough data is available
///
/// When reading a file via the `@io.Reader` interface,
/// the content of the file will be read as a byte stream.
/// The position of the read stream in the file is
/// independent of the write stream (via the `@io.Writer` interface)
pub impl @io.Reader for File with fn _direct_read(self, buf, offset~, max_len~) {
  self.io.read(buf, offset~, len=max_len, context="@fs.File::read()")
}

///|
pub impl @io.Reader for File with fn _get_internal_buffer(self) {
  self.read_buf
}

///|
/// Read from a file at the offset given by `position`.
/// Only seekable files (e.g. regular files and block devices) support this operation,
/// calling `read_at` on unsupported file, such as pipe or socket, result in error.
///
/// This function does not change the cursor for reading/writing the file
/// as a stream (i.e. using API based on `@io.Reader` and `@io.Writer`),
/// so it is safe to perform multiple `read_at` on the same file simutaneously.
///
/// Up to `len` bytes of data will be read into `buf[offset:]`.
/// The number of bytes actually read would be returned.
/// The number of read bytes will be smaller than `len` only when EOF is reached.
pub async fn File::read_at(
  self : File,
  buf : FixedArray[Byte],
  position~ : Int64,
  offset? : Int = 0,
  len? : Int = buf.length() - offset,
) -> Int {
  self.io.read_at(buf, offset~, len~, position~, context="@fs.File::read_at()")
}

///|
pub async fn File::read_exactly_at(
  self : File,
  len : Int,
  position~ : Int64,
) -> Bytes {
  let buf = FixedArray::make(len, b'\x00')
  let n = self.io.read_at(
    buf,
    offset=0,
    len~,
    position~,
    context="@fs.File::read_exactly_at()",
  )
  if n < len {
    raise @io.ReaderClosed
  }
  buf.unsafe_reinterpret_as_bytes()
}

///|
/// If the file is opened with `append=true`,
/// writing to the file via the `@io.Writer` interface
/// always append content at the end of the file.
///
/// If the file is opened with `append=false` (the default),
/// content written to the file via the `@io.Writer` interface
/// will be written as a byte stream, starting at offset 0.
/// The position of the write stream in the file is
/// independent of the read stream (via the `@io.Reader` interface)
pub impl @io.Writer for File with fn write_once(self, buf, offset~, len~) {
  self.io.write(buf, offset~, len~, context="@fs.File::write()")
}

///|
/// Write to a file at the offset given by `position`.
/// Only seekable files (e.g. regular files and block devices) support this operation,
/// calling `write_at` on unsupported file, such as pipe or socket, result in error.
///
/// This function does not change the cursor for reading/writing the file
/// as a stream (i.e. using API based on `@io.Reader` and `@io.Writer`),
/// so it is safe to perform multiple `write_at` on the same file simutaneously,
/// as long as the regions they write do not overlap.
///
/// `write_at` would only return after all data is written.
pub async fn File::write_at(
  self : File,
  buf : BytesView,
  position~ : Int64,
) -> Unit {
  self.io.write_at(
    buf.data(),
    offset=buf.start_offset(),
    len=buf.length(),
    position~,
    context="@fs.File::write_at()",
  )
}

///|
/// Flush all in-memory data of an opened file to disk.
/// If `only_data` is `true` (`false` by default),
/// some metadata such as timestamp may not be flushed.
/// Buf file content and important metadata such as file size are always flushed.
pub async fn File::sync(self : File, only_data? : Bool = false) -> Unit {
  self.io.fsync(only_data~, context="@fs.File::sync()")
}

///|
/// The kind of lock that can be acquired on a file.
/// `Exclusive` lock must be unique,
/// while multiple `Shared` lock can coexist.
/// `Exclusive` lock and `Shared` lock are mutually exclusive.
pub(all) enum Lock {
  Shared
  Exclusive
}

///|
/// Lock a file, block until the lock is successfully acquired.
///
/// The lock here is advisory, so normal read/write operations
/// on the file are not affected by the lock,
/// only another attempt to lock the same file may conflict with the lock here.
///
/// The underlying syscall used to implement the lock is undefined.
/// So the lock should only be used for synchronization between multiple process
/// written using `moonbitlang/async`.
pub async fn File::lock(self : File, lock : Lock) -> Unit {
  self.io.lock(exclusive=lock is Exclusive, context="@fs.File::lock()")
}

///|
#cfg(target="native")
extern "C" fn errno_is_lock_violation(err : Int) -> Bool = "moonbitlang_async_errno_is_lock_violation"

///|
#cfg(target="wasm")
#unsafe_skip_stub_check
fn errno_is_lock_violation(err : Int) -> Bool = "moonbitlang/async" "fs/errno_is_lock_violation"

///|
#cfg(target="native")
extern "C" fn try_lock_ffi(fd : @fd_util.Fd, exclusive~ : Bool) -> Int = "moonbitlang_async_try_lock_file"

///|
#cfg(target="wasm")
#unsafe_skip_stub_check
fn try_lock_ffi(fd : @fd_util.Fd, exclusive~ : Bool) -> Int = "moonbitlang/async" "fs/try_lock_file"

///|
/// Try to lock a file.
/// If the lock is successfully acquired, `true` is returned.
/// If the lock cannot be acquired immediately
/// (because an incompatible lock is held by another process),
/// `false` is returned immediately.
///
/// The lock here is advisory, so normal read/write operations
/// on the file are not affected by the lock,
/// only another attempt to lock the same file may conflict with the lock here.
///
/// The underlying syscall used to implement the lock is undefined.
/// So the lock should only be used for synchronization between multiple process
/// written using `moonbitlang/async`.
pub fn File::try_lock(self : File, lock : Lock) -> Bool raise {
  let ret = try_lock_ffi(self.fd(), exclusive=lock is Exclusive)
  if ret >= 0 {
    true
  } else if errno_is_lock_violation(@os_error.get_errno()) {
    false
  } else {
    @os_error.check_errno("@fs.File::try_lock()")
    false
  }
}

///|
#cfg(target="native")
extern "C" fn unlock_ffi(fd : @fd_util.Fd) -> Int = "moonbitlang_async_unlock_file"

///|
#cfg(target="wasm")
#unsafe_skip_stub_check
fn unlock_ffi(fd : @fd_util.Fd) -> Int = "moonbitlang/async" "fs/unlock_file"

///|
/// Unlock a file that was previously locked by this process.
pub fn File::unlock(self : File) -> Unit {
  if unlock_ffi(self.fd()) < 0 {
    // swallow the error so that we can use `unlock` in `defer`.
    // TODO: remove the `try!` after we support raising error in `defer`.
    try! @os_error.check_errno("@fs.File::unlock()")
  }
}

///|
/// Remove the file located at `path`. `path` is encoded using UTF8.
pub async fn remove(path : StringView) -> Unit {
  @event_loop.remove(path, context="@fs.remove()")
}

///|
/// Rename (move) the file located at `old_path` to `new_path`.
///
/// If `replace` is `true` (`true` by default),
/// and a file already exist on `new_path`, that file will be replaced.
/// In this case, open handles to the existing file remain valid,
/// and still point to the old file.
pub async fn rename(
  old_path : StringView,
  new_path : StringView,
  replace? : Bool = true,
) -> Unit {
  @event_loop.rename(old_path, new_path, replace~, context="@fs.rename()")
}

///|
/// Get the size of the file. This method will not change position in the file.
/// Can only be applied to a regular file.
pub async fn File::size(self : File) -> Int64 {
  @event_loop.file_size(self.io.fd(), context="@fs.File::size()")
}

///|
/// Convert a file to directory.
/// If the file is not a directory, an error will be raised.
///
/// The ownership of the file will be transferred to `as_dir`.
/// The input file will be automatically closed when the
/// result directory object is closed.
/// If `as_dir` fails, the input file will be closed automatically.
pub fn File::as_dir(self : File) -> Directory raise {
  guard self.io.kind() is Directory else {
    self.close()
    raise @os_error.OSError(
      @os_error.errno_ENOTDIR,
      context="@fs.File::as_dir()",
    )
  }
  Directory::from_io_handle(self.io)
}

///|
// mute unused warning
#cfg(platform="windows")
let _unused : Unit = ignore(@os_error.check_errno)

///|
pub fn File::kind(self : File) -> FileKind {
  FileKind::from_fd_util_file_kind(self.io.kind())
}

///|
/// Get the last access time of a file.
/// The return value is a pair `(s, ns)`,
/// representing the time of `s` seconds + `ns` nanoseconds.
pub async fn File::atime(self : File) -> (Int64, Int) {
  @event_loop.file_time(self.io.fd(), context="@fs.File::atime()").atime()
}

///|
/// Get the last modification time of a file.
/// The return value is a pair `(s, ns)`,
/// representing the time of `s` seconds + `ns` nanoseconds.
pub async fn File::mtime(self : File) -> (Int64, Int) {
  @event_loop.file_time(self.io.fd(), context="@fs.File::mtime()").mtime()
}

///|
/// Get the last status change time of a file.
/// The return value is a pair `(s, ns)`,
/// representing the time of `s` seconds + `ns` nanoseconds.
pub async fn File::ctime(self : File) -> (Int64, Int) {
  @event_loop.file_time(self.io.fd(), context="@fs.File::ctime()").ctime()
}

///|
/// Read a regular file using its current size as an allocation hint.
///
/// The size is not treated as EOF: pseudo files such as procfs entries may
/// report a size of zero, and a regular file may grow while it is being read.
/// Once the hinted region is full, keep reading in larger chunks until the
/// underlying file actually reports EOF.
async fn[R : @io.Reader] read_all_with_size_hint(
  reader : R,
  hinted_size : Int,
) -> &@io.Data {
  let hinted = FixedArray::make(hinted_size, b'0')
  let mut hinted_len = 0
  while hinted_len < hinted_size {
    let n = reader.read(
      hinted,
      offset=hinted_len,
      max_len=hinted_size - hinted_len,
    )
    if n == 0 {
      return hinted.unsafe_reinterpret_as_bytes()[:hinted_len].to_owned()
    }
    hinted_len += n
  }

  // The size returned by stat is only a hint. Probe for a real EOF without
  // allocating a large tail buffer in the common case.
  let probe = FixedArray::make(1, b'0')
  let probe_len = reader.read(probe, offset=0, max_len=1)
  if probe_len == 0 {
    return hinted.unsafe_reinterpret_as_bytes()
  }

  // Retain data appended after the stat call, as well as data from zero-sized
  // pseudo files such as entries in procfs.
  let chunk_size = 64 * 1024
  let chunks = []
  let mut chunk = FixedArray::make(chunk_size, b'0')
  chunk.unsafe_blit(0, probe, 0, probe_len)
  let mut chunk_len = probe_len
  while reader.read(chunk, offset=chunk_len, max_len=chunk.length() - chunk_len)
        is n &&
        n > 0 {
    chunk_len += n
    if chunk_len == chunk.length() {
      chunks.push(chunk)
      chunk = FixedArray::make(chunk_size, b'0')
      chunk_len = 0
    }
  }
  let tail_size = chunks.length().to_int64() * chunk_size.to_int64() +
    chunk_len.to_int64()
  guard hinted_size.to_int64() <= @int.MAX_VALUE.to_int64() - tail_size else {
    raise Failure::Failure("@fs.read_file(): file is too large")
  }
  let total_size = hinted_size + tail_size.to_int()
  let result = FixedArray::make(total_size, b'0')
  result.unsafe_blit(0, hinted, 0, hinted_size)
  for i, buf in chunks {
    result.unsafe_blit(hinted_size + i * chunk_size, buf, 0, chunk_size)
  }
  result.unsafe_blit(
    hinted_size + chunks.length() * chunk_size,
    chunk,
    0,
    chunk_len,
  )
  result.unsafe_reinterpret_as_bytes()
}

///|
async fn File::read_regular_to_end(self : File) -> &@io.Data {
  let size = self.size() catch {
    err if @async.is_being_cancelled() => raise err
    // A size is only an optimization hint. Some handles may be classified as
    // regular but not support querying a size, so preserve the streaming path.
    @os_error.OSError(_) => return self.read_all()
    err => raise err
  }
  guard size >= 0L && size <= @int.MAX_VALUE.to_int64() else {
    return self.read_all()
  }
  @coroutine.check_cancellation()
  read_all_with_size_hint(self, size.to_int())
}

///|
/// Read the contents of the file located at `path`.
/// If `sync_timestamp` is `true` (`false` by default),
/// `read_file` will block until timestamp change is written to the file system.
pub async fn read_file(
  path : StringView,
  sync_timestamp? : Bool = false,
) -> &@io.Data {
  let file = open(path, mode=ReadOnly)
  defer file.close()
  let result = if file.kind() is Regular {
    file.read_regular_to_end()
  } else {
    file.read_all()
  }
  if sync_timestamp {
    file.io.fsync(only_data=false, context="@fs.read_file(sync_timestamp=true)")
  }
  result
}

///|
/// Write data to a file located at `path`.
/// The meaning of `sync`, `append`, `create_mode` and `permission`,
/// is the same as `open`, except that `create_mode` is `TruncateExisting` by default.
/// See `open` for more details.
#label_migration(create, fill=false, msg="the option `create` is deprecated, use `create_mode` and `permission` instead")
#label_migration(truncate, fill=false, msg="the option `truncate` is deprecated, use `create_mode` instead")
pub async fn write_file(
  path : StringView,
  content : &@io.Data,
  create_mode? : CreateMode,
  permission? : Int,
  sync? : SyncMode = Data,
  append? : Bool = false,
  create? : Int,
  truncate? : Bool = true,
) -> Unit {
  let create_mode = match create_mode {
    Some(mode) => mode
    None =>
      match (create is Some(_), truncate) {
        (true, true) => CreateOrTruncate
        (true, false) => OpenOrCreate
        (false, true) => TruncateExisting
        (false, false) => OpenExisting
      }
  }
  let permission = match permission {
    Some(perm) => perm
    None if create is Some(perm) => perm
    None => 0o644
  }
  let file = open(
    path,
    mode=WriteOnly,
    sync~,
    append~,
    create_mode~,
    permission~,
  )
  defer file.close()
  file.write(content.binary())
}
