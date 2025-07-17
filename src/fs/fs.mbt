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
  truncate~ : Bool
) -> Int = "moonbitlang_async_make_open_flags"

///|
pub async fn open(
  filename : Bytes,
  mode~ : Mode,
  sync~ : SyncMode = NoSync,
  append~ : Bool = false,
  create? : Int,
  truncate~ : Bool = false
) -> File raise {
  let (create, user_mode) = match create {
    None => (false, 0)
    Some(mode) => (true, mode)
  }
  let flags = make_open_flags(mode~, sync~, append~, create~, truncate~)
  let job = @event_loop.make_open_job(filename, flags, user_mode)
  File(@event_loop.perform_job(job))
}

///|
pub async fn create(
  filename : Bytes,
  permission~ : Int,
  sync~ : SyncMode = NoSync
) -> File raise {
  open(filename, mode=WriteOnly, sync~, create=permission, truncate=true)
}

///|
pub async fn File::read(
  self : File,
  buf : FixedArray[Byte],
  len : Int
) -> Unit raise {
  let File(fd) = self
  let job = @event_loop.make_read_job(fd, buf, len)
  guard len == @event_loop.perform_job(job)
}

///|
pub async fn File::write(self : File, buf : Bytes, len : Int) -> Unit raise {
  let File(fd) = self
  let job = @event_loop.make_write_job(fd, buf, len)
  guard len == @event_loop.perform_job(job)
}
