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
pub(all) enum SyncMode {
  NoSync
  Data
  Full
}

///|
pub(all) enum CreateMode {
  OpenExisting = 0
  TruncateExisting = 1
  OpenOrCreate = 2
  CreateOrTruncate = 3
  CreateNew = 4
}

///|
fn CreateMode::to_int(self : CreateMode) -> Int = "%identity"

///|
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
pub impl @io.Reader for File with fn _direct_read(self, buf, offset~, max_len~) {
  self.io.read(buf, offset~, len=max_len, context="@fs.File::read()")
}

///|
pub impl @io.Reader for File with fn _get_internal_buffer(self) {
  self.read_buf
}

///|
pub impl @io.Writer for File with fn write_once(self, buf, offset~, len~) {
  self.io.write(buf, offset~, len~, context="@fs.File::write()")
}

///|
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
pub async fn read_file(
  path : StringView,
  sync_timestamp? : Bool = false,
) -> &@io.Data {
  let file = open(path, mode=ReadOnly)
  defer file.close()
  let result = file.read_all()
  if sync_timestamp {
    file.io.fsync(only_data=false, context="@fs.File::read_file(sync_timestamp=true)")
  }
  result
}

///|
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

///|
pub async fn remove(_path : StringView) -> Unit {
  abort("@fs.remove is not supported for wasm yet")
}

///|
pub async fn rename(
  _old_path : StringView,
  _new_path : StringView,
  replace? : Bool = true,
) -> Unit {
  ignore(replace)
  abort("@fs.rename is not supported for wasm yet")
}
