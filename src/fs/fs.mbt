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
pub(all) enum FileKind {
  Unknown = 0
  Regular = 1
  Directory = 2
  SymLink = 3
  Socket = 4
  Pipe = 5
  BlockDevice = 6
  CharDevice = 7
} derive(Show)

///|
struct File {
  fd : Int
  kind : FileKind
}

///|
pub fn File::close(self : File) -> Unit {
  @event_loop.close_fd(self.fd)
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
extern "C" fn make_open_flags(
  mode~ : Mode,
  sync~ : SyncMode,
  append~ : Bool,
  create~ : Bool,
  truncate~ : Bool,
) -> Int = "moonbitlang_async_make_open_flags"

///|
/// Open a file. `filename` should be a byte string and must not contain `'\0'`.
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
  filename : Bytes,
  mode~ : Mode,
  sync~ : SyncMode = NoSync,
  append~ : Bool = false,
  create? : Int,
  truncate~ : Bool = false,
) -> File raise {
  let (create, user_mode) = match create {
    None => (false, 0)
    Some(mode) => (true, mode)
  }
  let flags = make_open_flags(mode~, sync~, append~, create~, truncate~)
  let job = @event_loop.Open(path=filename, flags~, mode=user_mode)
  let fd = @event_loop.perform_job(job)
  let kind = get_file_kind_ffi(fd)
  if kind < 0 {
    @os_error.check_errno()
  }
  { fd, kind: FileKind::unsafe_from_int(kind) }
}

///|
/// Create a new file at `pathname`. `pathname` must not contain`'\0'`.
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
  filename : Bytes,
  permission~ : Int,
  sync~ : SyncMode = NoSync,
) -> File raise {
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
pub async fn File::read(
  self : File,
  buf : FixedArray[Byte],
  offset~ : Int = 0,
  len~ : Int = buf.length() - offset,
) -> Int raise {
  @event_loop.perform_job(Read(fd=self.fd, buf~, offset~, len~))
}

///|
/// `file.write(buf, offset~, len~)` write content of `buf[offset:offset+len]`
/// to the file `file`.
/// By default, `offset` is `0` and `len` is `buf.length() - offset`.
///
/// `write` will ensure all data is succesfully written,
/// Unless an error occurred while writing.
pub async fn File::write(
  self : File,
  buf : Bytes,
  offset~ : Int = 0,
  len~ : Int = buf.length() - offset,
) -> Unit raise {
  ignore(@event_loop.perform_job(Write(fd=self.fd, buf~, offset~, len~)))
}

///|
/// Remove the file located at `path`. `path` must not contain `'\0'`.
pub async fn remove(path : Bytes) -> Unit raise {
  let job = @event_loop.Remove(path~)
  ignore(@event_loop.perform_job(job))
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
extern "C" fn lseek_ffi(fd : Int, offset : Int64, whence : SeekMode) -> Int64 = "moonbitlang_async_lseek"

///|
/// Change current position in file for reading and writing.
/// Can only be applied to a regular file, otherwise `seek` will fail.
/// The offset is interpreted using `mode`, see `SeekMode` for more detail.
/// Current position in the file after seeking (relative to start of file)
/// will be returned.
pub fn File::seek(self : File, offset : Int64, mode~ : SeekMode) -> Int64 raise {
  let offset = lseek_ffi(self.fd, offset, mode)
  if offset < 0 {
    @os_error.check_errno()
  }
  offset
}

///|
/// Get current position in the file. Can only be applied to a regular file.
pub fn File::curr_pos(self : File) -> Int64 raise {
  self.seek(0, mode=Relative)
}

///|
/// Get the size of the file. This method will not change position in the file.
/// Can only be applied to a regular file.
pub fn File::size(self : File) -> Int64 raise {
  let curr_pos = self.curr_pos()
  let size = self.seek(0, mode=FromEnd)
  ignore(self.seek(curr_pos, mode=FromStart))
  size
}

///|
extern "C" fn as_dir_ffi(fd : Int) -> Directory = "fdopendir"

///|
/// Convert a file to directory.
/// If the file is not a directory, an error will be raised.
pub fn File::as_dir(self : File) -> Directory raise {
  let dir = as_dir_ffi(self.fd)
  if dir.is_null() {
    @os_error.check_errno()
  }
  dir
}

///|
fn FileKind::unsafe_from_int(x : Int) -> FileKind = "%identity"

///|
extern "C" fn get_file_kind_ffi(fd : Int) -> Int = "moonbitlang_async_file_kind"

///|
pub fn File::kind(self : File) -> FileKind {
  self.kind
}
