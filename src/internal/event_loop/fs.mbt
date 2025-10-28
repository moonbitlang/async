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
#external
pub type Directory

///|
#external
pub type DirectoryEntry

///|
pub async fn open(
  path : StringView,
  flags~ : Int,
  mode~ : Int,
  context~ : String,
) -> Int {
  let path_bytes = @encoding/utf8.encode(path)
  perform_job_in_worker(
    JobForWorker::open(path_bytes, flags, mode),
    context~,
    extra=Some(path),
  )
}

///|
pub async fn stat(
  path : StringView,
  follow_symlink~ : Bool,
  context~ : String,
) -> @fd_util.Stat {
  let path_bytes = @encoding/utf8.encode(path)
  let stat = @fd_util.Stat::new()
  let _ = perform_job_in_worker(
    JobForWorker::stat(path_bytes, stat, follow_symlink~),
    context~,
    extra=Some(path),
  )
  stat
}

///|
pub async fn access(path : StringView, amode~ : Int, context~ : String) -> Int {
  let path_bytes = @encoding/utf8.encode(path)
  perform_job_in_worker(
    JobForWorker::access(path_bytes, amode),
    context~,
    extra=Some(path),
  )
}

///|
pub async fn fsync(fd : Int, only_data~ : Bool, context~ : String) -> Unit {
  perform_job_in_worker(
    JobForWorker::fsync(fd, only_data),
    context~,
    extra=None,
  )
  |> ignore
}

///|
pub async fn remove(path : StringView, context~ : String) -> Unit {
  let path_bytes = @encoding/utf8.encode(path)
  perform_job_in_worker(
    JobForWorker::remove(path_bytes),
    context~,
    extra=Some(path),
  )
  |> ignore
}

///|
pub async fn mkdir(path : StringView, mode~ : Int, context~ : String) -> Unit {
  let path_bytes = @encoding/utf8.encode(path)
  perform_job_in_worker(
    JobForWorker::mkdir(path_bytes, mode),
    context~,
    extra=Some(path),
  )
  |> ignore
}

///|
pub async fn rmdir(path : StringView, context~ : String) -> Unit {
  let path_bytes = @encoding/utf8.encode(path)
  perform_job_in_worker(
    JobForWorker::rmdir(path_bytes),
    context~,
    extra=Some(path),
  )
  |> ignore
}

///|
extern "C" fn DirectoryEntry::null() -> DirectoryEntry = "moonbitlang_async_null_dirent"

///|
pub async fn readdir(dir : Directory, context~ : String) -> DirectoryEntry {
  let out = @ref.new(DirectoryEntry::null())
  let _ = perform_job_in_worker(
    JobForWorker::readdir(dir, out),
    context~,
    extra=None,
  )
  out.val
}

///|
pub async fn realpath(path : StringView, context~ : String) -> Bytes {
  let path_bytes = @encoding/utf8.encode(path)
  let out = @ref.new(@c_buffer.null)
  let _ = perform_job_in_worker(
    JobForWorker::realpath(path_bytes, out),
    context~,
    extra=Some(path),
  )
  let c_path = out.val
  defer c_path.free()
  let len = c_path.strlen()
  let result = FixedArray::make(len, b'\x00')
  c_path.blit_to_bytes(dst=result, offset=0, len~)
  result.unsafe_reinterpret_as_bytes()
}
