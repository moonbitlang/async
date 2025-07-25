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
/// A directory in file system
#external
type Directory

///|
extern "C" fn Directory::close_ffi(self : Directory) -> Int = "closedir"

///|
pub fn Directory::close(self : Directory) -> Unit {
  guard self.close_ffi() == 0
}

///|
extern "C" fn opendir_ffi(path : Bytes) -> Directory = "opendir"

///|
extern "C" fn Directory::is_null(dir : Directory) -> Bool = "moonbitlang_async_dir_is_null"

///|
/// Open the directory at `path`. `path` should be a `'\0'` terminated byte string.
/// If `path` is not a directory, an error will be raised
pub fn opendir(path : Bytes) -> Directory raise {
  let dir = opendir_ffi(path)
  if dir.is_null() {
    @os_error.check_errno()
  }
  dir
}

///|
#external
priv type DirectoryEntry

///|
extern "C" fn get_null_dirent() -> DirectoryEntry = "moonbitlang_async_null_dirent"

///|
let null_dirent : DirectoryEntry = get_null_dirent()

///|
extern "C" fn DirectoryEntry::name(ent : DirectoryEntry) -> Bytes = "moonbitlang_async_dirent_name"

///|
extern "C" fn readdir_job(
  dir : Directory,
  out : Ref[DirectoryEntry],
) -> @thread_pool.Job = "moonbitlang_async_make_readdir_job"

///|
async fn Directory::read_next(dir : Directory) -> Bytes? raise {
  let out = @ref.new(null_dirent)
  let job = readdir_job(dir, out)
  ignore(@event_loop.perform_job(job))
  if physical_equal(out.val, null_dirent) {
    None
  } else {
    Some(out.val.name())
  }
}

///|
/// Read all entries in a directory.
/// - If `include_special` is `true` (`false` by default),
///   `.` (current directory) and `..` (parent directory) will be included too
/// - If `include_hidden` is `true` (`true` by default),
///   directory entries starting with `.` (except `.` and `..`) will be included
pub async fn Directory::read_all(
  dir : Directory,
  include_hidden~ : Bool = true,
  include_special~ : Bool = false,
) -> Array[Bytes] raise {
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
