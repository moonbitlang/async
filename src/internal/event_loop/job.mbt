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
pub(all) enum Job {
  Read(
    fd~ : Int,
    buf~ : FixedArray[Byte],
    offset~ : Int,
    len~ : Int,
    can_poll~ : Bool
  )
  Write(fd~ : Int, buf~ : Bytes, offset~ : Int, len~ : Int, can_poll~ : Bool)
  Open(path~ : Bytes, flags~ : Int, mode~ : Int)
  Stat(path~ : Bytes, out~ : FixedArray[Byte], follow_symlink~ : Bool)
  Access(path~ : Bytes, amode~ : Int)
  Fsync(fd~ : Int, only_data~ : Bool)
  Remove(path~ : Bytes)
  Mkdir(path~ : Bytes, mode~ : Int)
  Rmdir(path~ : Bytes)
  Readdir(dir~ : Directory, out~ : Ref[DirectoryEntry])
  Realpath(path~ : Bytes, out~ : Ref[@c_buffer.Buffer])
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
