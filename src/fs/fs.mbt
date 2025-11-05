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
using @fd_util {type Stat}

///|
struct File(@event_loop.IOHandle)

///|
pub fn File::fd(self : File) -> Int {
  self.0.fd()
}

///|
pub fn File::close(self : File) -> Unit {
  self.0.close()
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
/// Open a file. `filename` will be encoded using UTF8.
///
/// - `mode` determines what operations (read/write) are permitted for the file.
///
/// - `sync` determines how data will be synchronized to disk after writing,
///   see `SyncMode` for more details. The default is `NoSync`
///
/// - if `append` is `true` (`false` by default), the file will be opened in append mode.
///
/// - if `create` is present and the file is not present,
///   the file will be created, with its user permission set to value of `create`.
///   User permission is represented as an integer in UNIX permission style.
///   For example, `0o640` means:
///   - the owner of the file can read and write the file (`6`)
///   - users in the owner group of the file can read the file (`4`)
///   - other users can do nothing to the file
///
/// - if `truncate` is `true` (`false` by default), and the file exists,
///   it will be truncated to zero length after opening.
pub async fn open(
  filename : StringView,
  mode~ : Mode,
  sync? : SyncMode = NoSync,
  append? : Bool = false,
  create? : Int,
  truncate? : Bool = false,
) -> File {
  let mut flags = match mode {
    ReadOnly => const_O_RDONLY
    WriteOnly => const_O_WRONLY
    ReadWrite => const_O_RDWR
  }
  let user_mode = match create {
    None => 0
    Some(mode) => {
      flags = flags | const_O_CREAT
      mode
    }
  }
  if append {
    flags = flags | const_O_APPEND
  }
  if truncate {
    flags = flags | const_O_TRUNC
  }
  match sync {
    NoSync => ()
    Data => flags = flags | const_O_DSYNC
    Full => flags = flags | const_O_SYNC
  }
  @event_loop.open(filename, flags~, mode=user_mode, context="@fs.open()")
}

///|
/// Create a new file at `pathname`. `pathname` will be encoded using UTF8.
///
/// - User permission of the new file would be set to `permission`,
///   which is an integer in UNIX style. For example, `0o640` means:
///     - the owner of the file can read and write the file (`6`)
///     - users in the owner group of the file can read the file (`4`)
///     - other users can do nothing to the file
///
/// - `sync` determines how data will be synchronized to disk after writing,
///   see `SyncMode` for more details. The default is `NoSync`
pub async fn create(
  filename : StringView,
  permission~ : Int,
  sync? : SyncMode = NoSync,
) -> File {
  open(filename, mode=WriteOnly, sync~, create=permission, truncate=true)
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
pub impl @io.Reader for File with read(
  self,
  buf,
  offset? = 0,
  max_len? = buf.length() - offset,
) {
  self.0.read(buf, offset~, len=max_len, context="@fs.File::read()")
}

///|
// used for obtaining the default implementation of `@io.Reader::read_all`
priv struct DummyFile(File)

///|
impl @io.Reader for DummyFile with read(
  self,
  buf,
  offset? = 0,
  max_len? = buf.length() - offset,
) {
  @io.Reader::read(self.0, buf, offset~, max_len~)
}

///|
pub impl @io.Reader for File with read_all(self) {
  match self.0.kind() {
    Regular => {
      let size = self.size().to_int()
      let result = FixedArray::make(size, b'0')
      guard self.read(result) == size
      result.unsafe_reinterpret_as_bytes() as &@io.Data
    }
    _ => @io.Reader::read_all(DummyFile(self))
  }
}

///|
pub impl @io.Writer for File with write_once(self, buf, offset~, len~) {
  self.0.write(buf, offset~, len~, context="@fs.File::write()")
}

///|
/// Flush all in-memory data of an opened file to disk.
/// If `only_data` is `true` (`false` by default),
/// some metadata such as timestamp may not be flushed.
/// Buf file content and important metadata such as file size are always flushed.
pub async fn File::sync(self : File, only_data? : Bool = false) -> Unit {
  self.0.fsync(only_data~, context="@fs.File::sync()")
}

///|
/// Remove the file located at `path`. `path` is encoded using UTF8.
pub async fn remove(path : StringView) -> Unit {
  @event_loop.remove(path, context="@fs.remove()")
}

///|
/// Determine how an offset is interpreted when seeking in a file:
/// - `FromStart`: absolute offset from the start of the file
/// - `FromEnd`: offset is relative to end of file
/// - `Relative`: offset is relative to current position in the file
pub(all) enum SeekMode {
  FromStart = 0
  FromEnd
  Relative
}

///|
fn SeekMode::to_int(self : SeekMode) -> Int = "%identity"

///|
/// Change current position in file for reading and writing.
/// Can only be applied to a regular file, otherwise `seek` will fail.
/// The offset is interpreted using `mode`, see `SeekMode` for more detail.
/// Current position in the file after seeking (relative to start of file)
/// will be returned.
pub async fn File::seek(self : File, offset : Int64, mode~ : SeekMode) -> Int64 {
  self.0.seek(offset, mode.to_int(), context="@fs.File::seek()")
}

///|
/// Get current position in the file. Can only be applied to a regular file.
pub async fn File::curr_pos(self : File) -> Int64 {
  self.seek(0, mode=Relative)
}

///|
/// Get the size of the file. This method will not change position in the file.
/// Can only be applied to a regular file.
pub async fn File::size(self : File) -> Int64 {
  self.0.fstat(context="@fs.File::size()").size()
}

///|
extern "C" fn as_dir_ffi(fd : Int) -> Directory = "fdopendir"

///|
extern "C" fn Directory::is_null(dir : Directory) -> Bool = "moonbitlang_async_dir_is_null"

///|
/// Convert a file to directory.
/// If the file is not a directory, an error will be raised.
///
/// The ownership of the file will be transferred to `as_dir`.
/// So the caller MUST NOT use or close the file after calling `as_dir`,
/// even if `as_dir` fails.
/// Caller should call `.close()` on the returned directory object instead
/// (or, if `as_dir` fails, the input file is closed automatically).
pub fn File::as_dir(self : File) -> Directory raise {
  let fd = self.0.detach_from_event_loop()
  let dir = as_dir_ffi(fd)
  if dir.is_null() {
    let context = "@fs.File::as_dir()"
    @fd_util.close(fd, context~)
    @os_error.check_errno(context)
  }
  dir
}

///|
pub fn File::kind(self : File) -> FileKind {
  FileKind::from_fd_util_file_kind(self.0.kind())
}

///|
/// Get the last access time of a file.
/// The return value is a pair `(s, ns)`,
/// representing the time of `s` seconds + `ns` nanoseconds.
pub async fn File::atime(self : File) -> (Int64, Int) {
  self.0.fstat(context="@fs.File::atime()").atime()
}

///|
/// Get the last modification time of a file.
/// The return value is a pair `(s, ns)`,
/// representing the time of `s` seconds + `ns` nanoseconds.
pub async fn File::mtime(self : File) -> (Int64, Int) {
  self.0.fstat(context="@fs.File::mtime()").mtime()
}

///|
/// Get the last status change time of a file.
/// The return value is a pair `(s, ns)`,
/// representing the time of `s` seconds + `ns` nanoseconds.
pub async fn File::ctime(self : File) -> (Int64, Int) {
  self.0.fstat(context="@fs.File::ctime()").ctime()
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
  let result = file.read_all()
  if sync_timestamp {
    file.0.fsync(
      only_data=false,
      context="@fs.File::read_file(sync_timestamp=true)",
    )
  }
  result
}

///|
/// Read the contents of a text file located at `path`.
#deprecated("use `read_file(path).text()` instead")
pub async fn read_text_file(
  path : StringView,
  encoding~ : @io.Encoding,
) -> String {
  guard encoding is UTF8
  read_file(path).text()
}

///|
/// Write data to a file located at `path`.
/// The meaning of `sync`, `append`, `create`, and `truncate`,
/// is the same as `open`, except that `truncate` is `true` by default.
/// See `open` for more details.
pub async fn write_file(
  path : StringView,
  content : &@io.Data,
  sync? : SyncMode = Data,
  append? : Bool = false,
  create? : Int,
  truncate? : Bool = true,
) -> Unit {
  let file = open(path, mode=WriteOnly, sync~, append~, create?, truncate~)
  defer file.close()
  file.write(content.binary())
}

///|
/// Write data to a text file located at `path`.
/// The meaning of `sync`, `append`, `create`, truncate` is the same as `open`,
/// except that `truncate` is `true` by default. See `open` for more details.
#deprecated("use `write_file(path, content)` instead")
pub async fn write_text_file(
  path : StringView,
  content : String,
  encoding~ : @io.Encoding,
  sync? : SyncMode = Data,
  append? : Bool = false,
  create? : Int,
  truncate? : Bool = true,
) -> Unit {
  let file = open(path, mode=WriteOnly, sync~, append~, create?, truncate~)
  defer file.close()
  file.write_string(content, encoding~)
}
