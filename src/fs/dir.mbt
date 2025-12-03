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
pub async fn mkdir(path : StringView, permission~ : Int) -> Unit {
  @event_loop.mkdir(path, mode=permission, context="@fs.mkdir()")
}

///|
/// Remove a directory at `path`,
/// If `recursive` is `true` (`false` by default),
/// files and directories in `path` will be removed recursively.
/// If `recursive` is `false`,
/// `path` must be an empty directory, otherwise `rmdir` will fail.
pub async fn rmdir(path : StringView, recursive? : Bool = false) -> Unit {
  let context = "@fs.rmdir()"
  if recursive {
    let base = path.to_string()
    for file in readdir(base) {
      let child_path = base + "/" + file
      let stat = @event_loop.stat(child_path, follow_symlink=false, context~)
      if stat.kind() is Directory {
        rmdir(child_path, recursive=true)
      } else {
        @event_loop.remove(child_path, context~)
      }
    }
  }
  @event_loop.rmdir(path, context~)
}

///|
/// A directory in file system
#external
type Directory

///|
#external
priv type DirectoryEntry

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
async fn opendir_aux(path : StringView, context~ : String) -> Directory {
  struct Job {
    path : Bytes
    mut result : Directory
    mut err : Int
  }
  let path_bytes = @encoding/utf8.encode(path)
  let job : Job = { path: path_bytes, result: @c_buffer.null_ptr(), err: 0 }
  @event_loop.perform_job_in_worker(job, job => {
    job.result = opendir_ffi(job.path)
    job.err = @os_error.get_errno()
  }) catch {
    err => {
      if !@c_buffer.ptr_is_null(job.result) {
        ignore(job.result.close_ffi())
      }
      raise err
    }
  }
  if @c_buffer.ptr_is_null(job.result) {
    raise @os_error.OSError(job.err, context="\{context}: \{repr(path)}")
  }
  job.result
}

///|
/// Open the directory at `path`. `path` is encoded UTF8.
/// If `path` is not a directory, an error will be raised
pub async fn opendir(path : StringView) -> Directory {
  opendir_aux(path, context="@fs.opendir()")
}

///|
extern "C" fn DirectoryEntry::name(ent : DirectoryEntry) -> Bytes = "moonbitlang_async_dirent_name"

///|
extern "C" fn readdir_ffi(dir : Directory) -> DirectoryEntry = "readdir"

///|
async fn Directory::read_next(dir : Directory) -> String? {
  struct Job {
    dir : Directory
    mut result : DirectoryEntry
    mut err : Int
  }
  let job : Job = { dir, result: @c_buffer.null_ptr(), err: 0 }
  @event_loop.perform_job_in_worker(job, job => {
    @os_error.clear_errno()
    job.result = readdir_ffi(job.dir)
    job.err = @os_error.get_errno()
  })
  if job.err != 0 {
    raise @os_error.OSError(job.err, context="@fs.readdir()")
  } else if @c_buffer.ptr_is_null(job.result) {
    None
  } else {
    Some(@encoding/utf8.decode(job.result.name()))
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
  path : StringView,
  include_hidden? : Bool = true,
  include_special? : Bool = false,
  sort? : Bool = false,
) -> Array[String] {
  let dir : Directory = opendir_aux(path, context="@fs.readdir()")
  defer dir.close()
  let list = dir.read_all(include_hidden~, include_special~)
  if sort {
    list.sort()
  }
  list
}

///|
/// `walk(path, f, ..)` recursively walk the directory `path`,
/// and call `f` on every sub-directory in `path`, including `path` itself.
///
/// The directories are walked in parallel.
/// Use `max_concurrency` to limit the number of workers spawned in parallel.
/// For example, setting `max_concurrency=1` result in sequential walking.
/// By default `max_concurrency` is set to a large value.
///
/// If `allow_failure` is `true` (`false` by default),
/// error raised by `f` will be silently ignored.
/// Otherwise, failure in `f` will stop the whole `walk`,
/// cancelling the handling of other sub-directories.
pub async fn walk(
  path : StringView,
  f : async (String, Array[String]) -> Unit,
  max_concurrency? : Int = 1000,
  allow_failure? : Bool = false,
) -> Unit {
  guard max_concurrency > 0
  let sem = @semaphore.Semaphore::new(max_concurrency)
  @async.with_task_group(fn(group) {
    async fn handle_path(path : String) {
      group.spawn_bg(allow_failure~, fn() {
        sem.acquire()
        defer sem.release()
        let files = readdir(path)
        for file in files {
          let file_path = if path is [.., '/'] {
            path + file
          } else {
            "\{path}/\{file}"
          }
          if kind(file_path) is Directory {
            handle_path(file_path)
          }
        }
        f(path, files)
      })
    }

    handle_path(path.to_string())
  })
}
