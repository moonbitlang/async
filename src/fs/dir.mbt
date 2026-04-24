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
///
/// The Unix-style permission of the created directory can be set in `permission`,
/// the default value is `0o755` (anyone can read and traverse, only owner can write).
/// The `permission` parameter is currently ignored on Windows.
///
/// If `recursive=true` (`false` by default), non-existing parent directories
/// of `path` will be recursively created, too.
pub async fn mkdir(
  path : StringView,
  permission? : Int = 0o755,
  recursive? : Bool = false,
) -> Unit {
  let context = "@fs.mkdir()"
  @event_loop.mkdir(path, mode=permission, context~) catch {
    @os_error.OSError(_) as err if recursive && err.is_ENOENT() => {
      let last_path_sep_index = match path.rev_find("/") {
        Some(index) => index
        None if @event_loop.IS_WINDOWS && path.rev_find("\\") is Some(index) =>
          index
        None => raise err
      }
      let parent = path[:last_path_sep_index].trim_end(chars="/")
      let parent = if @event_loop.IS_WINDOWS {
        parent.trim_end(chars="\\")
      } else {
        parent
      }
      mkdir(parent, permission~, recursive~)
      @event_loop.mkdir(path, mode=permission, context~)
    }
    err => raise err
  }
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
    let dir = opendir_aux(path, context~)
    defer dir.close()
    while dir.next_aux(include_special=false, include_hidden=true, context~)
          is Some(ent) {
      let child_path = base + "/" + ent.name
      if ent.is_dir {
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
struct Directory {
  fd : @fd_util.Fd
  buf : FixedArray[Byte]
  mut offset : Int
  mut buf_len : Int
  mut completed : Bool
}

///|
pub fn Directory::close(self : Directory) -> Unit {
  @fd_util.close(self.fd, kind=Directory, context="") catch {
    _ => ()
  }
}

///|
/// Open the directory at `path`. `path` is encoded UTF8.
/// If `path` is not a directory, an error will be raised
pub async fn opendir(path : StringView) -> Directory {
  opendir_aux(path, context="@fs.opendir()")
}

///|
async fn opendir_aux(path : StringView, context~ : String) -> Directory {
  let (fd, kind) = @event_loop.open_detached(
    path,
    0,
    create=0,
    append=false,
    sync=0,
    mode=0,
    context~,
  )
  if !(kind is Directory) {
    @fd_util.close(fd, kind~, context~)
    raise @os_error.OSError(
      @os_error.errno_ENOTDIR,
      context="\{context}: \{path.escape()}",
    )
  }
  {
    fd,
    buf: FixedArray::make(1024, b'\x00'),
    offset: 0,
    buf_len: 0,
    completed: false,
  }
}

///|
#borrow(buf)
extern "C" fn Directory::entry_length(
  buf : FixedArray[Byte],
  offset : Int,
  len : Int,
) -> Int = "moonbitlang_async_dir_entry_length"

///|
#borrow(buf)
extern "C" fn Directory::entry_name(
  buf : FixedArray[Byte],
  offset : Int,
) -> @c_buffer.Buffer = "moonbitlang_async_dir_entry_get_name"

///|
#borrow(buf)
extern "C" fn Directory::entry_is_dir(
  buf : FixedArray[Byte],
  offset : Int,
) -> Int = "moonbitlang_async_dir_entry_is_dir"

///|
#borrow(buf)
extern "C" fn Directory::entry_is_hidden(
  buf : FixedArray[Byte],
  offset : Int,
) -> Bool = "moonbitlang_async_dir_entry_is_hidden"

///|
#valtype
pub struct DirectoryEntry {
  name : String
  is_dir : Bool
}

///|
pub async fn Directory::next(
  dir : Directory,
  include_hidden? : Bool = true,
  include_special? : Bool = false,
) -> DirectoryEntry? {
  dir.next_aux(
    include_special~,
    include_hidden~,
    context="@fs.Directory::next()",
  )
}

///|
async fn Directory::next_aux(
  dir : Directory,
  include_hidden~ : Bool,
  include_special~ : Bool,
  context~ : String,
) -> DirectoryEntry? {
  guard !dir.completed else { None }
  let entry_len = Directory::entry_length(dir.buf, dir.offset, dir.buf_len)
  let entry_len = if entry_len is 0 {
    dir.offset = 0
    dir.buf_len = @event_loop.readdir(
      dir.fd,
      dir.buf,
      dir.buf.length(),
      context~,
    )
    Directory::entry_length(dir.buf, dir.offset, dir.buf_len)
  } else {
    entry_len
  }
  guard entry_len > 0 else {
    dir.completed = true
    None
  }
  let offset = dir.offset
  dir.offset += entry_len
  if !include_hidden && Directory::entry_is_hidden(dir.buf, offset) {
    return dir.next_aux(include_special~, include_hidden~, context~)
  }
  let name = @os_string.decode(Directory::entry_name(dir.buf, offset))
  if !include_special && name is ("." | "..") {
    return dir.next_aux(include_special~, include_hidden~, context~)
  }
  let is_dir = match Directory::entry_is_dir(dir.buf, offset) {
    0 => false
    1..<_ => true
    _..<0 => {
      let kind = @event_loop.file_kind_by_path(
        name,
        parent=dir.fd,
        follow_symlink=false,
        context~,
      )
      kind is Directory
    }
  }
  Some({ name, is_dir })
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
  let context = "@fs.Directory::read_all()"
  while dir.next_aux(include_hidden~, include_special~, context~) is Some(entry) {
    result.push(entry.name)
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
  let context = "@fs.readdir()"
  let dir : Directory = opendir_aux(path, context~)
  defer dir.close()
  let list = []
  while dir.next_aux(include_hidden~, include_special~, context~) is Some(entry) {
    list.push(entry.name)
  }
  if sort {
    list.sort()
  }
  list
}

///|
/// `walk(path, f, ..)` recursively walk the directory `path`,
/// and call `f` on every sub-directory in `path`, including `path` itself.
///
/// If `exclude` is present, it will be invoked with the path of every directory
/// before traversing them. If `exclude` returns `true`,
/// the directory and all its children will be skipped.
/// The path passed to `exclude` has the following format:
/// - always start with `path`
/// - does not contain trailing directory separator
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
  exclude? : (String) -> Bool = _ => false,
  max_concurrency? : Int = 1000,
  allow_failure? : Bool = false,
) -> Unit {
  let context = "@fs.walk()"
  guard max_concurrency > 0
  let sem = @async.Semaphore::new(max_concurrency)
  @async.with_task_group(fn(group) {
    fn handle_path(path : String) {
      guard !exclude(path) else {  }
      group.spawn_bg(allow_failure~, () => {
        sem.acquire()
        defer sem.release()
        let dir = opendir_aux(path, context~)
        let files = []
        while dir.next_aux(include_hidden=true, include_special=false, context~)
              is Some(ent) {
          let file_path = if path is [.., '/'] {
            path + ent.name
          } else {
            "\{path}/\{ent.name}"
          }
          if ent.is_dir {
            handle_path(file_path)
          }
          files.push(ent.name)
        }
        f(path, files)
      })
    }

    handle_path(path.to_string())
  })
}
