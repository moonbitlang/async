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
pub async fn kind(path : StringView, follow_symlink? : Bool = true) -> FileKind {
  @event_loop.stat(path, follow_symlink~, context="@fs.kind()").kind()
  |> FileKind::from_int
}

///|
/// Get the last access time of a file at `path`.
/// The return value is a pair `(s, ns)`,
/// representing the time of `s` seconds + `ns` nanoseconds.
///
/// If `follow_symlink` is `true` (`true` by default) and `path` is a symbolic link,
/// the timestamp of the target of `path` will be returned.
pub async fn atime(
  path : StringView,
  follow_symlink? : Bool = true,
) -> (Int64, Int) {
  @event_loop.stat(path, follow_symlink~, context="@fs.atime()").atime()
}

///|
/// Get the last modification time of a file at `path`.
/// The return value is a pair `(s, ns)`,
/// representing the time of `s` seconds + `ns` nanoseconds.
///
/// If `follow_symlink` is `true` (`true` by default) and `path` is a symbolic link,
/// the timestamp of the target of `path` will be returned.
pub async fn mtime(
  path : StringView,
  follow_symlink? : Bool = true,
) -> (Int64, Int) {
  @event_loop.stat(path, follow_symlink~, context="@fs.mtime()").mtime()
}

///|
/// Get the last status change time of a file at `path`.
/// The return value is a pair `(s, ns)`,
/// representing the time of `s` seconds + `ns` nanoseconds.
///
/// If `follow_symlink` is `true` (`true` by default) and `path` is a symbolic link,
/// the timestamp of the target of `path` will be returned.
pub async fn ctime(
  path : StringView,
  follow_symlink? : Bool = true,
) -> (Int64, Int) {
  @event_loop.stat(path, follow_symlink~, context="@fs.ctime()").ctime()
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
pub async fn exists(path : StringView) -> Bool {
  try @event_loop.access(path, amode=f_ok(), context="@fs.exists()") catch {
    @os_error.OSError(_) as err if err.is_ENOENT() => false
    err => raise err
  } noraise {
    _ => true
  }
}

///|
pub async fn can_read(path : StringView) -> Bool {
  try @event_loop.access(path, amode=r_ok(), context="@fs.can_read()") catch {
    @os_error.OSError(_) as err if err.is_ENOENT() => false
    @os_error.OSError(_) as err if err.is_EACCES() => false
    err => raise err
  } noraise {
    _ => true
  }
}

///|
pub async fn can_write(path : StringView) -> Bool {
  try @event_loop.access(path, amode=w_ok(), context="@fs.can_write()") catch {
    @os_error.OSError(_) as err if err.is_ENOENT() => false
    @os_error.OSError(_) as err if err.is_EACCES() => false
    err => raise err
  } noraise {
    _ => true
  }
}

///|
pub async fn can_execute(path : StringView) -> Bool {
  try @event_loop.access(path, amode=x_ok(), context="@fs.can_execute") catch {
    @os_error.OSError(_) as err if err.is_ENOENT() => false
    @os_error.OSError(_) as err if err.is_EACCES() => false
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
pub async fn realpath(path : StringView) -> String {
  let result = @event_loop.realpath(path, context="@fs.realpath()")
  @encoding/utf8.decode(result)
}
