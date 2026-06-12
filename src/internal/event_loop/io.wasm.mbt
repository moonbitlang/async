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
struct IoHandle {
  mut fd : @fd_util.Fd
  kind : @fd_util.FileKind
}

///|
pub fn IoHandle::from_fd(
  fd : @fd_util.Fd,
  kind~ : @fd_util.FileKind,
  is_async? : Bool = false,
) -> IoHandle raise {
  ignore(is_async)
  { fd, kind }
}

///|
pub fn IoHandle::fd(handle : IoHandle) -> @fd_util.Fd {
  handle.fd
}

///|
pub fn IoHandle::kind(handle : IoHandle) -> @fd_util.FileKind {
  handle.kind
}

///|
pub fn IoHandle::close(handle : IoHandle) -> Unit {
  if @fd_util.fd_is_valid(handle.fd) {
    @fd_util.close(handle.fd, kind=handle.kind, context="") catch {
      _ => ()
    }
  }
  handle.fd = @fd_util.invalid_fd
}

///|
pub async fn IoHandle::read(
  handle : IoHandle,
  buf : FixedArray[Byte],
  offset~ : Int,
  len~ : Int,
  context~ : String,
) -> Int {
  let job = Job::read(handle.fd, buf, offset, len, position=-1)
  defer job.free()
  perform_job_in_worker(job, context~)
}

///|
pub async fn IoHandle::read_at(
  handle : IoHandle,
  buf : FixedArray[Byte],
  offset~ : Int,
  len~ : Int,
  position~ : Int64,
  context~ : String,
) -> Int {
  let job = Job::read(handle.fd, buf, offset, len, position~)
  defer job.free()
  perform_job_in_worker(job, context~)
}

///|
pub async fn IoHandle::write(
  handle : IoHandle,
  buf : Bytes,
  offset~ : Int,
  len~ : Int,
  context~ : String,
) -> Int {
  let job = Job::write(handle.fd, buf, offset, len, position=-1)
  defer job.free()
  perform_job_in_worker(job, context~)
}

///|
pub async fn IoHandle::write_at(
  handle : IoHandle,
  buf : Bytes,
  offset~ : Int,
  len~ : Int,
  position~ : Int64,
  context~ : String,
) -> Unit {
  let job = Job::write(handle.fd, buf, offset, len, position~)
  defer job.free()
  perform_job_in_worker(job, context~) |> ignore
}
