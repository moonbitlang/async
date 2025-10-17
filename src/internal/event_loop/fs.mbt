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
pub(all) struct Stat(Bytes)

///|
pub fn Stat::new() -> Stat {
  Bytes::make(sizeof_stat(), 0)
}

///|
pub async fn open(
  path : Bytes,
  flags~ : Int,
  mode~ : Int,
  context~ : String,
) -> Int {
  perform_job_in_worker(JobForWorker::open(path, flags, mode), context~)
}

///|
extern "C" fn sizeof_stat() -> Int = "moonbitlang_async_sizeof_stat"

///|
pub async fn stat(
  path : Bytes,
  follow_symlink~ : Bool,
  context~ : String,
) -> Stat {
  let out = FixedArray::make(sizeof_stat(), b'\x00')
  let _ = perform_job_in_worker(
    JobForWorker::stat(path, out, follow_symlink~),
    context~,
  )
  out.unsafe_reinterpret_as_bytes()
}

///|
pub async fn access(path : Bytes, amode~ : Int, context~ : String) -> Int {
  perform_job_in_worker(JobForWorker::access(path, amode), context~)
}

///|
pub async fn fsync(fd : Int, only_data~ : Bool, context~ : String) -> Unit {
  perform_job_in_worker(JobForWorker::fsync(fd, only_data), context~) |> ignore
}

///|
pub async fn remove(path : Bytes, context~ : String) -> Unit {
  perform_job_in_worker(JobForWorker::remove(path), context~) |> ignore
}

///|
pub async fn mkdir(path : Bytes, mode~ : Int, context~ : String) -> Unit {
  perform_job_in_worker(JobForWorker::mkdir(path, mode), context~) |> ignore
}

///|
pub async fn rmdir(path : Bytes, context~ : String) -> Unit {
  perform_job_in_worker(JobForWorker::rmdir(path), context~) |> ignore
}

///|
extern "C" fn DirectoryEntry::null() -> DirectoryEntry = "moonbitlang_async_null_dirent"

///|
pub async fn readdir(dir : Directory, context~ : String) -> DirectoryEntry {
  let out = @ref.new(DirectoryEntry::null())
  let _ = perform_job_in_worker(JobForWorker::readdir(dir, out), context~)
  out.val
}

///|
pub async fn realpath(path : Bytes, context~ : String) -> Bytes {
  let out = @ref.new(@c_buffer.null)
  let _ = perform_job_in_worker(JobForWorker::realpath(path, out), context~)
  let c_path = out.val
  defer c_path.free()
  let len = c_path.strlen()
  let result = FixedArray::make(len, b'\x00')
  c_path.blit_to_bytes(dst=result, offset=0, len~)
  result.unsafe_reinterpret_as_bytes()
}
