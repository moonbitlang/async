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
pub(all) enum FileKind {
  Unknown = 0
  Regular = 1
  Directory = 2
  SymLink = 3
  Socket = 4
  Pipe = 5
  BlockDevice = 6
  CharDevice = 7
} derive(Eq, Debug)

///|
pub fn FileKind::unsafe_from_int(value : Int) -> FileKind = "%identity"

///|
pub fn FileKind::can_poll(self : FileKind) -> Bool {
  match self {
    Socket | Pipe | CharDevice => true
    Unknown | Regular | Directory | SymLink | BlockDevice => false
  }
}

///|
struct FileTime(FixedArray[Byte])

///|
fn FileTime::size() -> Int = "moonbit_v0" "sizeof_file_time"

///|
pub fn FileTime::new() -> FileTime {
  FixedArray::make(FileTime::size(), b'\x00')
}

///|
fn get_atime_sec_ffi(ptr : Int) -> Int64 = "moonbit_v0" "get_atime_sec"

///|
fn get_atime_nsec_ffi(ptr : Int) -> Int = "moonbit_v0" "get_atime_nsec"

///|
fn get_mtime_sec_ffi(ptr : Int) -> Int64 = "moonbit_v0" "get_mtime_sec"

///|
fn get_mtime_nsec_ffi(ptr : Int) -> Int = "moonbit_v0" "get_mtime_nsec"

///|
fn get_ctime_sec_ffi(ptr : Int) -> Int64 = "moonbit_v0" "get_ctime_sec"

///|
fn get_ctime_nsec_ffi(ptr : Int) -> Int = "moonbit_v0" "get_ctime_nsec"

///|
#borrow(self)
pub fn FileTime::ptr(self : FileTime) -> Int {
  let FileTime(buf) = self
  @wasm_ffi.byte_array_to_ptr(buf)
}

///|
#borrow(self)
pub fn FileTime::length(self : FileTime) -> Int {
  let FileTime(buf) = self
  buf.length()
}

///|
pub fn FileTime::atime(self : FileTime) -> (Int64, Int) {
  let ptr = self.ptr()
  (get_atime_sec_ffi(ptr), get_atime_nsec_ffi(ptr))
}

///|
pub fn FileTime::mtime(self : FileTime) -> (Int64, Int) {
  let ptr = self.ptr()
  (get_mtime_sec_ffi(ptr), get_mtime_nsec_ffi(ptr))
}

///|
pub fn FileTime::ctime(self : FileTime) -> (Int64, Int) {
  let ptr = self.ptr()
  (get_ctime_sec_ffi(ptr), get_ctime_nsec_ffi(ptr))
}
