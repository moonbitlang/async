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
} derive(Eq, Show)

///|
// currently we cannot re-export constructors,
// so we have to use a hack to make the `FileKind` type available to users.
fn FileKind::from_fd_util_file_kind(k : @fd_util.FileKind) -> FileKind = "%identity"

///|
#cfg(not(platform="windows"))
let const_F_OK : Int = get_F_OK()

///|
#cfg(not(platform="windows"))
let const_R_OK : Int = get_R_OK()

///|
#cfg(not(platform="windows"))
let const_W_OK : Int = get_W_OK()

///|
#cfg(not(platform="windows"))
let const_X_OK : Int = get_X_OK()

///|
#cfg(not(platform="windows"))
extern "C" fn get_F_OK() -> Int = "moonbitlang_async_get_F_OK"

///|
#cfg(not(platform="windows"))
extern "C" fn get_R_OK() -> Int = "moonbitlang_async_get_R_OK"

///|
#cfg(not(platform="windows"))
extern "C" fn get_W_OK() -> Int = "moonbitlang_async_get_W_OK"

///|
#cfg(not(platform="windows"))
extern "C" fn get_X_OK() -> Int = "moonbitlang_async_get_X_OK"
