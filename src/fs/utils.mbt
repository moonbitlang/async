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
pub async fn kind(path : Bytes) -> FileKind {
  let stat = FixedArray::make(sizeof_stat(), b'0')
  let _ = @event_loop.perform_job(Stat(path~, out=stat))
  file_kind_from_stat(stat)
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
pub async fn exists(path : Bytes) -> Bool {
  try @event_loop.perform_job(Access(path~, amode=f_ok())) catch {
    @os_error.OSError(code) if code == _ENOENT => false
    err => raise err
  } noraise {
    _ => true
  }
}

///|
pub async fn can_read(path : Bytes) -> Bool {
  try @event_loop.perform_job(Access(path~, amode=r_ok())) catch {
    @os_error.OSError(code) if code == _ENOENT => false
    @os_error.OSError(code) if code == _EACCES => false
    err => raise err
  } noraise {
    _ => true
  }
}

///|
pub async fn can_write(path : Bytes) -> Bool {
  try @event_loop.perform_job(Access(path~, amode=w_ok())) catch {
    @os_error.OSError(code) if code == _ENOENT => false
    @os_error.OSError(code) if code == _EACCES => false
    err => raise err
  } noraise {
    _ => true
  }
}

///|
pub async fn can_execute(path : Bytes) -> Bool {
  try @event_loop.perform_job(Access(path~, amode=x_ok())) catch {
    @os_error.OSError(code) if code == _ENOENT => false
    @os_error.OSError(code) if code == _EACCES => false
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
pub async fn realpath(path : Bytes) -> Bytes {
  let out = @ref.new(@c_buffer.null)
  let _ = @event_loop.perform_job(Realpath(path~, out~))
  let c_path = out.val
  defer c_path.free()
  let len = c_path.strlen()
  let result = FixedArray::make(len, (0 : Byte))
  c_path.blit_to_bytes(dst=result, offset=0, len~)
  result.unsafe_reinterpret_as_bytes()
}
