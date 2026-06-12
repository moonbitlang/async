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
        None if @event_loop.is_windows() && path.rev_find("\\") is Some(index) =>
          index
        None => raise err
      }
      let parent = path[:last_path_sep_index].trim_end(chars="/")
      let parent = if @event_loop.is_windows() {
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
pub async fn rmdir(path : StringView, recursive? : Bool = false) -> Unit {
  let context = "@fs.rmdir()"
  if recursive {
    let base = if @event_loop.is_windows() {
      path.trim_end(chars="/\\")
    } else {
      path.trim_end(chars="/")
    }
    let dir = opendir_aux(path, context~)
    defer dir.close()
    while dir.next_aux(include_special=false, include_hidden=true, context~)
          is Some(ent) {
      let child_path = "\{base}/\{ent.name}"
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
priv enum DirectoryState {
  NoMoreEntry
  NeedMoreEntry
  HasBufferedEntry
}

///|
struct Directory {
  io : @event_loop.IoHandle
  buf : FixedArray[Byte]
  mut offset : Int
  mut job_ret : Int
  mut state : DirectoryState
}

///|
pub fn Directory::close(self : Directory) -> Unit {
  self.io.close()
}

///|
fn dir_buffer_min_size_ffi() -> Int = "moonbit_v0" "fs/dir_buffer_min_size"

///|
fn Directory::min_buffer_size() -> Int {
  dir_buffer_min_size_ffi()
}

///|
pub async fn opendir(path : StringView) -> Directory {
  opendir_aux(path, context="@fs.opendir()")
}

///|
async fn opendir_aux(path : StringView, context~ : String) -> Directory {
  let (io, _) = @event_loop.open(
    path,
    0,
    create=0,
    append=false,
    sync=0,
    mode=0,
    context~,
  )
  if !(io.kind() is Directory) {
    io.close()
    raise @os_error.OSError(
      @os_error.errno_ENOTDIR,
      context="\{context}: \{path.escape()}",
    )
  }
  Directory::from_io_handle(io)
}

///|
fn Directory::from_io_handle(io : @event_loop.IoHandle) -> Directory {
  {
    io,
    buf: FixedArray::make(
      @cmp.maximum(Directory::min_buffer_size(), 1024),
      b'\x00',
    ),
    offset: 0,
    job_ret: 0,
    state: NeedMoreEntry,
  }
}

///|
fn dir_entry_length_ffi(buf : Int, offset : Int) -> Int = "moonbit_v0" "fs/dir_entry_length"

///|
fn dir_entry_name_len_ffi(buf : Int, offset : Int) -> Int = "moonbit_v0" "fs/dir_entry_get_name_len"

///|
fn dir_entry_name_ffi(buf : Int, offset : Int) -> @c_buffer.Buffer = "moonbit_v0" "fs/dir_entry_get_name"

///|
fn dir_entry_is_dir_ffi(buf : Int, offset : Int) -> Int = "moonbit_v0" "fs/dir_entry_is_dir"

///|
fn dir_entry_is_hidden_ffi(buf : Int, offset : Int) -> Bool = "moonbit_v0" "fs/dir_entry_is_hidden"

///|
fn dir_entry_file_id_ffi(buf : Int, offset : Int) -> UInt64 = "moonbit_v0" "fs/dir_entry_get_file_id"

///|
#borrow(buf)
fn Directory::entry_length(buf : FixedArray[Byte], offset : Int) -> Int {
  dir_entry_length_ffi(@wasm_ffi.byte_array_to_ptr(buf), offset)
}

///|
#borrow(buf)
fn Directory::entry_name_len(buf : FixedArray[Byte], offset : Int) -> Int {
  dir_entry_name_len_ffi(@wasm_ffi.byte_array_to_ptr(buf), offset)
}

///|
#borrow(buf)
fn Directory::entry_name(
  buf : FixedArray[Byte],
  offset : Int,
) -> @c_buffer.Buffer {
  dir_entry_name_ffi(@wasm_ffi.byte_array_to_ptr(buf), offset)
}

///|
#borrow(buf)
fn Directory::entry_is_dir(buf : FixedArray[Byte], offset : Int) -> Int {
  dir_entry_is_dir_ffi(@wasm_ffi.byte_array_to_ptr(buf), offset)
}

///|
#borrow(buf)
fn Directory::entry_is_hidden(buf : FixedArray[Byte], offset : Int) -> Bool {
  dir_entry_is_hidden_ffi(@wasm_ffi.byte_array_to_ptr(buf), offset)
}

///|
#borrow(buf)
fn Directory::entry_file_id(buf : FixedArray[Byte], offset : Int) -> UInt64 {
  dir_entry_file_id_ffi(@wasm_ffi.byte_array_to_ptr(buf), offset)
}

///|
#valtype
pub struct DirectoryEntry {
  name : String
  is_dir : Bool
  priv file_id : UInt64
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
  restart? : Bool = false,
  context~ : String,
) -> DirectoryEntry? {
  match dir.state {
    NoMoreEntry => return None
    HasBufferedEntry => ()
    NeedMoreEntry => {
      dir.offset = 0
      dir.job_ret = dir.io.readdir(
        dir.buf,
        dir.buf.length(),
        restart~,
        context~,
      )
      if dir.job_ret is 0 {
        dir.state = NoMoreEntry
        return None
      } else {
        dir.state = HasBufferedEntry
      }
    }
  }
  let entry_len = Directory::entry_length(dir.buf, dir.offset)
  let offset = dir.offset
  dir.offset += entry_len
  if dir.offset >= dir.job_ret {
    dir.state = NeedMoreEntry
  }
  if !include_hidden && Directory::entry_is_hidden(dir.buf, offset) {
    return dir.next_aux(include_special~, include_hidden~, context~)
  }
  let name = @os_string.decode(
    Directory::entry_name(dir.buf, offset),
    len=Directory::entry_name_len(dir.buf, offset),
  )
  if !include_special && name is ("." | "..") {
    return dir.next_aux(include_special~, include_hidden~, context~)
  }
  let is_dir = match Directory::entry_is_dir(dir.buf, offset) {
    0 => false
    1..<_ => true
    _..<0 => {
      let kind = @event_loop.file_kind_by_path(
        name,
        parent=dir.io.fd(),
        follow_symlink=false,
        context~,
      )
      kind is Directory
    }
  }
  let file_id = Directory::entry_file_id(dir.buf, offset)
  Some({ name, is_dir, file_id })
}

///|
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
pub async fn walk(
  path : StringView,
  f : async (String, Array[String]) -> Unit,
  exclude? : (String) -> Bool = _ => false,
  max_concurrency? : Int = 1000,
  allow_failure? : Bool = false,
) -> Unit {
  let context = "@fs.walk()"
  guard max_concurrency > 0
  let sem = @async.Semaphore(max_concurrency)
  @async.with_task_group() <| fn(group) {
    fn handle_path(path : String) {
      guard !exclude(path) else {  }
      group.spawn_bg(allow_failure~) <| () => {
        sem.acquire()
        defer sem.release()
        let dir = opendir_aux(path, context~)
        defer dir.close()
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
      }
    }

    handle_path(path.to_owned())
  }
}
