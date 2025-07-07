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
extern "C" fn make_tcp_socket() -> Int = "make_tcp_socket"

///|
extern "C" fn make_udp_socket() -> Int = "make_udp_socket"

///|
extern "C" fn bind_ffi(sock : Int, ip : UInt, port : Int) -> Int = "bind_ffi"

///|
extern "C" fn listen_ffi(sock : Int) -> Int = "listen_ffi"

///|
extern "C" fn accept_ffi(sock : Int) -> Int = "accept_ffi"

///|
extern "C" fn connect_ffi(sock : Int, ip : UInt, port : Int) -> Int = "connect_ffi"

///|
#borrow(buf)
extern "C" fn recv_ffi(
  sock : Int,
  buf : FixedArray[Byte],
  offset : Int,
  max_len : Int
) -> Int = "recv_ffi"

///|
#borrow(buf)
extern "C" fn send_ffi(
  sock : Int,
  buf : Bytes,
  offset : Int,
  max_len : Int
) -> Int = "send_ffi"

///|
extern "C" fn get_socket_err(sock : Int) -> Int = "getsockerr"

///|
fn check_socket_err(sock : Int) -> Unit raise {
  if get_socket_err(sock) != 0 {
    @os_error.check_errno()
  }
}
