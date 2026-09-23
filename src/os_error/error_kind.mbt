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
#non_exhaustive
pub(all) enum Kind {
  FileNotFound
  AlreadyExists
  AccessDenied
  NotDirectory
  ConnectionRefused
  OperationNotSupported
  // TODO: add private constructor support & make `Unknown` private
  Unknown
} derive(Debug, ToJson, Eq)

///|
let errno_table : Map[Int, Kind] = match @env_util.platform {
  Linux =>
    Map([
      (linux_ENOENT, FileNotFound),
      (linux_EEXIST, AlreadyExists),
      (linux_EACCES, AccessDenied),
      (linux_ENOTDIR, NotDirectory),
      (linux_ECONNREFUSED, ConnectionRefused),
      (linux_ENOTSUP, OperationNotSupported),
    ])
  MacOS =>
    Map([
      (macos_ENOENT, FileNotFound),
      (macos_EEXIST, AlreadyExists),
      (macos_EACCES, AccessDenied),
      (macos_ENOTDIR, NotDirectory),
      (macos_ECONNREFUSED, ConnectionRefused),
      (macos_ENOTSUP, OperationNotSupported),
    ])
  Windows =>
    Map([
      (windows_ERROR_FILE_NOT_FOUND, FileNotFound),
      (windows_ERROR_PATH_NOT_FOUND, FileNotFound),
      (windows_ERROR_FILE_EXISTS, AlreadyExists),
      (windows_ERROR_ALREADY_EXISTS, AlreadyExists),
      (windows_ERROR_ACCESS_DENIED, AccessDenied),
      (windows_ERROR_DIRECTORY, NotDirectory),
      (windows_ERROR_CONNECTION_REFUSED, ConnectionRefused),
      (windows_ERROR_NOT_SUPPORTED, OperationNotSupported),
    ])
}

///|
fn Kind::Kind(code : Int) -> Kind {
  match errno_table.get(code) {
    None => Unknown
    Some(kind) => kind
  }
}
