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
type File Int

///|
pub fn File::close(self : File) -> Unit {
  let File(fd) = self
  @event_loop.close_fd(fd)
}

///|
pub(all) enum Mode {
  ReadOnly = 0
  WriteOnly
  ReadWrite
}

///|
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
  let job = @thread_pool.open_job(filename, flags, user_mode)
  File(@event_loop.perform_job(job))
}

///|
pub async fn create(
  filename : Bytes,
  permission~ : Int,
  sync~ : SyncMode = NoSync,
) -> File raise {
  open(filename, mode=WriteOnly, sync~, create=permission, truncate=true)
}

///|
pub async fn File::read(
  self : File,
  buf : FixedArray[Byte],
  offset~ : Int = 0,
  len? : Int,
) -> Unit raise {
  let File(fd) = self
  let len = len.unwrap_or(buf.length() - offset)
  let job = @thread_pool.read_job(fd, buf, offset, len)
  guard len == @event_loop.perform_job(job)
}

///|
pub async fn File::write(
  self : File,
  buf : Bytes,
  offset~ : Int = 0,
  len? : Int,
) -> Unit raise {
  let File(fd) = self
  let len = len.unwrap_or(buf.length())
  let job = @thread_pool.write_job(fd, buf, offset, len)
  guard len == @event_loop.perform_job(job)
}

///|
pub async fn remove(path : Bytes) -> Unit raise {
  let job = @thread_pool.remove_job(path)
  ignore(@event_loop.perform_job(job))
}

///|
pub(all) enum SeekMode {
  FromStart = 0
  FromEnd
  Relative
}

///|
extern "C" fn lseek_ffi(fd : Int, offset : Int64, whence : SeekMode) -> Int64 = "moonbitlang_async_lseek"

///|
pub fn File::seek(self : File, offset : Int64, mode~ : SeekMode) -> Int64 raise {
  let File(fd) = self
  let offset = lseek_ffi(fd, offset, mode)
  if offset < 0 {
    @os_error.check_errno()
  }
  offset
}

///|
pub fn File::curr_pos(self : File) -> Int64 raise {
  self.seek(0, mode=Relative)
}

///|
pub fn File::size(self : File) -> Int64 raise {
  let curr_pos = self.curr_pos()
  let size = self.seek(0, mode=FromEnd)
  ignore(self.seek(curr_pos, mode=FromStart))
  size
}
