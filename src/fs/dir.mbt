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
/// Create a directory at `path`.
/// The permission of the created directory must be set in `permission`.
pub async fn mkdir(path : String, permission~ : Int) -> Unit {
  let path = @encoding/utf8.encode(path)
  ignore(@event_loop.perform_job(Mkdir(path~, mode=permission)))
}

///|
/// Remove a directory at `path`,
/// If `recursive` is `true` (`false` by default),
/// files and directories in `path` will be removed recursively.
/// If `recursive` is `false`,
/// `path` must be an empty directory, otherwise `rmdir` will fail.
pub async fn rmdir(path : String, recursive? : Bool = false) -> Unit {
  if recursive {
    for file in readdir(path) {
      let file = path + "/" + file
      if kind(file) is Directory {
        rmdir(file, recursive=true)
      } else {
        remove(file)
      }
    }
  }
  let path = @encoding/utf8.encode(path)
  ignore(@event_loop.perform_job(Rmdir(path~)))
}

///|
/// A directory in file system
struct Directory(@event_loop.Directory)

///|
extern "C" fn Directory::close_ffi(self : Directory) -> Int = "closedir"

///|
pub fn Directory::close(self : Directory) -> Unit {
  guard self.close_ffi() == 0
}

///|
#borrow(path)
extern "C" fn opendir_ffi(path : Bytes) -> Directory = "opendir"

///|
extern "C" fn Directory::is_null(dir : Directory) -> Bool = "moonbitlang_async_dir_is_null"

///|
/// Open the directory at `path`. `path` is encoded UTF8.
/// If `path` is not a directory, an error will be raised
pub fn opendir(path : String) -> Directory raise {
  let path = @encoding/utf8.encode(path)
  let dir = opendir_ffi(path)
  if dir.is_null() {
    @os_error.check_errno()
  }
  dir
}

///|
typealias @event_loop.DirectoryEntry

///|
extern "C" fn get_null_dirent() -> DirectoryEntry = "moonbitlang_async_null_dirent"

///|
let null_dirent : DirectoryEntry = get_null_dirent()

///|
extern "C" fn DirectoryEntry::name(ent : DirectoryEntry) -> Bytes = "moonbitlang_async_dirent_name"

///|
async fn Directory::read_next(dir : Directory) -> String? {
  let out = @ref.new(null_dirent)
  ignore(@event_loop.perform_job(Readdir(dir=dir.0, out~)))
  if physical_equal(out.val, null_dirent) {
    None
  } else {
    Some(@encoding/utf8.decode(out.val.name()))
  }
}

///|
/// Read all entries in a directory.
/// - If `include_special` is `true` (`false` by default),
///   `.` (current directory) and `..` (parent directory) will be included too
/// - If `include_hidden` is `true` (`true` by default),
///   directory entries starting with `.` (except `.` and `..`) will be included
/// All returned directory entries are encoded using UTF8.
pub async fn Directory::read_all(
  dir : Directory,
  include_hidden? : Bool = true,
  include_special? : Bool = false,
) -> Array[String] {
  let result = []
  while dir.read_next() is Some(entry) {
    if not(include_special) && entry is ("." | "..") {
      continue
    }
    if not(include_hidden) && entry is ['.', ..] {
      continue
    }
    result.push(entry)
  }
  result
}

///|
/// Read all entries in the directory located at `path`.
/// - If `include_special` is `true` (`false` by default),
///   `.` (current directory) and `..` (parent directory) will be included too
/// - If `include_hidden` is `true` (`true` by default),
///   directory entries starting with `.` (except `.` and `..`) will be included
/// - If `sort` is `true` (`false` by default),
///   the result will be sorted using `Array::sort`.
pub async fn readdir(
  path : String,
  include_hidden? : Bool = true,
  include_special? : Bool = false,
  sort? : Bool = false,
) -> Array[String] {
  let dir = opendir(path)
  defer dir.close()
  let list = dir.read_all(include_hidden~, include_special~)
  if sort {
    list.sort()
  }
  list
}
