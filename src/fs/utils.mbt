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
/// Get the kind of a file at `path`.
/// If `path` is a symbolic link and `follow_symlink` is `true` (`true` by default),
/// the kind of the target of the link will be returned.
pub async fn kind(path : String, follow_symlink? : Bool = true) -> FileKind {
  Stat::from_path(path, follow_symlink~, context="@fs.kind()").kind()
}

///|
/// Get the last access time of a file at `path`.
/// The return value is a pair `(s, ns)`,
/// representing the time of `s` seconds + `ns` nanoseconds.
///
/// If `follow_symlink` is `true` (`true` by default) and `path` is a symbolic link,
/// the timestamp of the target of `path` will be returned.
pub async fn atime(
  path : String,
  follow_symlink? : Bool = true,
) -> (Int64, Int) {
  Stat::from_path(path, follow_symlink~, context="@fs.atime()").atime()
}

///|
/// Get the last modification time of a file at `path`.
/// The return value is a pair `(s, ns)`,
/// representing the time of `s` seconds + `ns` nanoseconds.
///
/// If `follow_symlink` is `true` (`true` by default) and `path` is a symbolic link,
/// the timestamp of the target of `path` will be returned.
pub async fn mtime(
  path : String,
  follow_symlink? : Bool = true,
) -> (Int64, Int) {
  Stat::from_path(path, follow_symlink~, context="@fs.mtime()").mtime()
}

///|
/// Get the last status change time of a file at `path`.
/// The return value is a pair `(s, ns)`,
/// representing the time of `s` seconds + `ns` nanoseconds.
///
/// If `follow_symlink` is `true` (`true` by default) and `path` is a symbolic link,
/// the timestamp of the target of `path` will be returned.
pub async fn ctime(
  path : String,
  follow_symlink? : Bool = true,
) -> (Int64, Int) {
  Stat::from_path(path, follow_symlink~, context="@fs.ctime()").ctime()
}

///|
extern "C" fn f_ok() -> Int = "moonbitlang_async_f_ok"

///|
extern "C" fn r_ok() -> Int = "moonbitlang_async_r_ok"

///|
extern "C" fn w_ok() -> Int = "moonbitlang_async_w_ok"

///|
extern "C" fn x_ok() -> Int = "moonbitlang_async_x_ok"

///|
extern "C" fn get_ENOENT() -> Int = "moonbitlang_async_get_ENOENT"

///|
let _ENOENT : Int = get_ENOENT()

///|
extern "C" fn get_EACCES() -> Int = "moonbitlang_async_get_EACCES"

///|
let _EACCES : Int = get_EACCES()

///|
pub async fn exists(path : String) -> Bool {
  try @event_loop.access(path, amode=f_ok(), context="@fs.exists()") catch {
    @os_error.OSError(code, ..) if code == _ENOENT => false
    err => raise err
  } noraise {
    _ => true
  }
}

///|
pub async fn can_read(path : String) -> Bool {
  try @event_loop.access(path, amode=r_ok(), context="@fs.can_read()") catch {
    @os_error.OSError(code, ..) if code == _ENOENT => false
    @os_error.OSError(code, ..) if code == _EACCES => false
    err => raise err
  } noraise {
    _ => true
  }
}

///|
pub async fn can_write(path : String) -> Bool {
  try @event_loop.access(path, amode=w_ok(), context="@fs.can_write()") catch {
    @os_error.OSError(code, ..) if code == _ENOENT => false
    @os_error.OSError(code, ..) if code == _EACCES => false
    err => raise err
  } noraise {
    _ => true
  }
}

///|
pub async fn can_execute(path : String) -> Bool {
  try @event_loop.access(path, amode=x_ok(), context="@fs.can_execute") catch {
    @os_error.OSError(code, ..) if code == _ENOENT => false
    @os_error.OSError(code, ..) if code == _EACCES => false
    err => raise err
  } noraise {
    _ => true
  }
}

///|
/// Get the absolute real path of `path`,
/// removing all `..` and `.` in the `path`,
/// and unfold all symbolic links.
///
/// If the path contains cyclic symbolic link,
/// an error will be raised.
pub async fn realpath(path : String) -> String {
  let result = @event_loop.realpath(path, context="@fs.realpath()")
  @encoding/utf8.decode(result)
}
