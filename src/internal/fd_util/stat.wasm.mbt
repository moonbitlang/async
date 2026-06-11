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
pub fn FileTime::new() -> FileTime {
  FixedArray::make(0, b'\x00')
}

///|
pub fn FileTime::atime(_self : FileTime) -> (Int64, Int) {
  (0, 0)
}

///|
pub fn FileTime::mtime(_self : FileTime) -> (Int64, Int) {
  (0, 0)
}

///|
pub fn FileTime::ctime(_self : FileTime) -> (Int64, Int) {
  (0, 0)
}
