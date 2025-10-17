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
priv struct Stat(@event_loop.Stat)

///|
fn Stat::new() -> Stat {
  @event_loop.Stat::new()
}

///|
#borrow(stat)
extern "C" fn Stat::from_fd_ffi(fd : Int, stat : Stat) -> Int = "fstat"

///|
fn Stat::from_fd(fd : Int, context~ : String) -> Stat raise {
  let stat = Stat::new()
  if Stat::from_fd_ffi(fd, stat) < 0 {
    @os_error.check_errno(context)
  }
  stat
}

///|
async fn Stat::from_path(
  path : String,
  follow_symlink~ : Bool,
  context~ : String,
) -> Stat {
  let path = @encoding/utf8.encode(path)
  @event_loop.stat(path, follow_symlink~, context~)
}

///|
#borrow(stat)
extern "C" fn Stat::kind(stat : Stat) -> FileKind = "moonbitlang_async_file_kind_from_stat"

///|
#borrow(stat, sec_out, nsec_out)
extern "C" fn Stat::atime_ffi(
  stat : Stat,
  sec_out : Ref[Int64],
  nsec_out : Ref[Int],
) = "moonbitlang_async_atime_from_stat"

///|
fn Stat::atime(stat : Stat) -> (Int64, Int) {
  let sec = @ref.new(0L)
  let nsec = @ref.new(0)
  stat.atime_ffi(sec, nsec)
  (sec.val, nsec.val)
}

///|
#borrow(stat, sec_out, nsec_out)
extern "C" fn Stat::mtime_ffi(
  stat : Stat,
  sec_out : Ref[Int64],
  nsec_out : Ref[Int],
) = "moonbitlang_async_mtime_from_stat"

///|
fn Stat::mtime(stat : Stat) -> (Int64, Int) {
  let sec = @ref.new(0L)
  let nsec = @ref.new(0)
  stat.mtime_ffi(sec, nsec)
  (sec.val, nsec.val)
}

///|
#borrow(stat, sec_out, nsec_out)
extern "C" fn Stat::ctime_ffi(
  stat : Stat,
  sec_out : Ref[Int64],
  nsec_out : Ref[Int],
) = "moonbitlang_async_ctime_from_stat"

///|
fn Stat::ctime(stat : Stat) -> (Int64, Int) {
  let sec = @ref.new(0L)
  let nsec = @ref.new(0)
  stat.ctime_ffi(sec, nsec)
  (sec.val, nsec.val)
}
