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
  Console = 8
} derive(Eq, Debug)

///|
let known_kinds : ReadOnlyArray[FileKind] = [
  Regular,
  Directory,
  SymLink,
  Socket,
  Pipe,
  BlockDevice,
  CharDevice,
  Console,
]

///|
pub fn FileKind::from_int(value : Int32) -> FileKind {
  if value >= 1 && value - 1 < known_kinds.length() {
    known_kinds[value - 1]
  } else {
    Unknown
  }
}

///|
pub fn FileKind::can_poll(self : FileKind) -> Bool {
  match self {
    Socket | Pipe | CharDevice | Console => true
    Unknown | Regular | Directory | SymLink | BlockDevice => false
  }
}
