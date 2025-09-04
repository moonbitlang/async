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
priv type JobForWorker

///|
#borrow(self)
extern "C" fn JobForWorker::id(self : JobForWorker) -> Int = "moonbitlang_async_job_get_id"

///|
#borrow(self)
extern "C" fn JobForWorker::ret(self : JobForWorker) -> Int = "moonbitlang_async_job_get_ret"

///|
#borrow(self)
extern "C" fn JobForWorker::err(self : JobForWorker) -> Int = "moonbitlang_async_job_get_err"

///|
extern "C" fn JobForWorker::sleep(time : Int) -> JobForWorker = "moonbitlang_async_make_sleep_job"

///|
#owned(buf)
extern "C" fn JobForWorker::read(
  fd : Int,
  buf : FixedArray[Byte],
  offset : Int,
  len : Int,
) -> JobForWorker = "moonbitlang_async_make_read_job"

///|
#owned(buf)
extern "C" fn JobForWorker::write(
  fd : Int,
  buf : Bytes,
  offset : Int,
  len : Int,
) -> JobForWorker = "moonbitlang_async_make_write_job"

///|
#owned(filename)
extern "C" fn JobForWorker::open(
  filename : Bytes,
  flags : Int,
  mode : Int,
) -> JobForWorker = "moonbitlang_async_make_open_job"

///|
#owned(path, out)
extern "C" fn JobForWorker::stat(
  path : Bytes,
  out : FixedArray[Byte],
) -> JobForWorker = "moonbitlang_async_make_stat_job"

///|
#owned(path)
extern "C" fn JobForWorker::remove(path : Bytes) -> JobForWorker = "moonbitlang_async_make_remove_job"

///|
#external
pub type Directory

///|
#external
pub type DirectoryEntry

///|
#owned(out)
extern "C" fn JobForWorker::readdir(
  dir : Directory,
  out : Ref[DirectoryEntry],
) -> JobForWorker = "moonbitlang_async_make_readdir_job"

///|
#owned(path, args, env, cwd)
extern "C" fn JobForWorker::spawn(
  path : Bytes,
  args : FixedArray[Bytes?],
  env : FixedArray[Bytes?],
  stdin : Int,
  stdout : Int,
  stderr : Int,
  cwd : Bytes?,
) -> JobForWorker = "moonbitlang_async_make_spawn_job"

///|
#owned(buf, addr)
extern "C" fn JobForWorker::recvfrom(
  sock : Int,
  buf : FixedArray[Byte],
  offset : Int,
  len : Int,
  addr : Bytes,
) -> JobForWorker = "moonbitlang_async_make_recvfrom_job"

///|
#owned(buf, addr)
extern "C" fn JobForWorker::sendto(
  sock : Int,
  buf : Bytes,
  offset : Int,
  len : Int,
  addr : Bytes,
) -> JobForWorker = "moonbitlang_async_make_sendto_job"

///|
#external
pub type AddrInfo

///|
type AddrInfoRef

///|
pub extern "C" fn AddrInfoRef::new() -> AddrInfoRef = "moonbitlang_async_addrinfo_ref_make"

///|
#borrow(self)
pub extern "C" fn AddrInfoRef::get_and_clear(self : AddrInfoRef) -> AddrInfo = "moonbitlang_async_addrinfo_ref_get"

///|
#owned(host, out)
extern "C" fn JobForWorker::getaddrinfo(
  host : Bytes,
  out : AddrInfoRef,
) -> JobForWorker = "moonbitlang_async_make_getaddrinfo_job"

///|
pub(all) enum Job {
  Sleep(Int)
  Read(
    fd~ : Int,
    buf~ : FixedArray[Byte],
    offset~ : Int,
    len~ : Int,
    can_poll~ : Bool
  )
  Write(fd~ : Int, buf~ : Bytes, offset~ : Int, len~ : Int, can_poll~ : Bool)
  Open(path~ : Bytes, flags~ : Int, mode~ : Int)
  Stat(path~ : Bytes, out~ : FixedArray[Byte])
  Remove(path~ : Bytes)
  Readdir(dir~ : Directory, out~ : Ref[DirectoryEntry])
  Spawn(
    path~ : Bytes,
    args~ : FixedArray[Bytes?],
    env~ : FixedArray[Bytes?],
    stdin~ : Int,
    stdout~ : Int,
    stderr~ : Int,
    cwd~ : Bytes?
  )
  Recvfrom(
    sock~ : Int,
    buf~ : FixedArray[Byte],
    offset~ : Int,
    len~ : Int,
    addr~ : Bytes
  )
  Sendto(sock~ : Int, buf~ : Bytes, offset~ : Int, len~ : Int, addr~ : Bytes)
  Connect(sock~ : Int, addr~ : Bytes)
  Accept(sock~ : Int, addr~ : Bytes)
  WaitProcess(Int)
  GetAddrInfo(host~ : Bytes, out~ : AddrInfoRef)
}
