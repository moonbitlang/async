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
pub async fn open(filename : Bytes, flags : Int) -> File raise {
  let job = @event_loop.make_open_job(filename, flags)
  File(@event_loop.perform_job(job))
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
