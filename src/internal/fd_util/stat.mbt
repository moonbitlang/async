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
struct Stat(FixedArray[Byte])

///|
extern "C" fn sizeof_stat() -> Int = "moonbitlang_async_sizeof_stat"

///|
pub fn Stat::new() -> Stat {
  FixedArray::make(sizeof_stat(), b'\x00')
}

///|
#borrow(stat)
extern "C" fn fstat_sync_ffi(fd : Int, stat : Stat) -> Int = "fstat"

///|
pub fn fstat_sync(fd : Int, context~ : String) -> Stat raise {
  let stat = Stat::new()
  if fstat_sync_ffi(fd, stat) < 0 {
    @os_error.check_errno(context)
  }
  stat
}

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
pub fn FileKind::can_poll(self : FileKind) -> Bool {
  match self {
    Socket | Pipe | CharDevice => true
    Unknown | Regular | Directory | SymLink | BlockDevice => false
  }
}

///|
#borrow(stat)
pub extern "C" fn Stat::kind(stat : Stat) -> FileKind = "moonbitlang_async_file_kind_from_stat"

///|
#borrow(stat)
pub extern "C" fn Stat::size(stat : Stat) -> Int64 = "moonbitlang_async_file_size_from_stat"

///|
#borrow(stat, sec_out, nsec_out)
extern "C" fn Stat::atime_ffi(
  stat : Stat,
  sec_out : Ref[Int64],
  nsec_out : Ref[Int],
) = "moonbitlang_async_atime_from_stat"

///|
pub fn Stat::atime(stat : Stat) -> (Int64, Int) {
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
pub fn Stat::mtime(stat : Stat) -> (Int64, Int) {
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
pub fn Stat::ctime(stat : Stat) -> (Int64, Int) {
  let sec = @ref.new(0L)
  let nsec = @ref.new(0)
  stat.ctime_ffi(sec, nsec)
  (sec.val, nsec.val)
}
