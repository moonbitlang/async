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
#borrow(stat)
extern "C" fn file_kind_from_stat(stat : FixedArray[Byte]) -> FileKind = "moonbitlang_async_file_kind_from_stat"

///|
extern "C" fn sizeof_stat() -> Int = "moonbitlang_async_sizeof_stat"

///|
pub async fn kind(path : Bytes) -> FileKind raise {
  let stat = FixedArray::make(sizeof_stat(), b'0')
  let _ = @event_loop.perform_job(Stat(path~, out=stat))
  file_kind_from_stat(stat)
}
