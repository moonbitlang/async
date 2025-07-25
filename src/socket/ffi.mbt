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
extern "C" fn make_socket(domain : Int, ty : Int, protocol : Int) -> Int = "moonbitlang_async_make_socket"

///|
#borrow(addr)
extern "C" fn bind_ffi(sock : Int, addr : IpAddr) -> Int = "moonbitlang_async_bind"

///|
extern "C" fn listen_ffi(sock : Int) -> Int = "moonbitlang_async_listen"

///|
#borrow(addr_buf)
extern "C" fn accept_ffi(sock : Int, addr_buf : IpAddr) -> Int = "moonbitlang_async_accept"

///|
#borrow(addr)
extern "C" fn connect_ffi(sock : Int, addr : IpAddr) -> Int = "moonbitlang_async_connect"

///|
#borrow(buf)
extern "C" fn recv_ffi(
  sock : Int,
  buf : FixedArray[Byte],
  offset : Int,
  max_len : Int,
) -> Int = "moonbitlang_async_recv"

///|
#borrow(buf)
extern "C" fn send_ffi(
  sock : Int,
  buf : Bytes,
  offset : Int,
  max_len : Int,
) -> Int = "moonbitlang_async_send"

///|
extern "C" fn get_socket_err(sock : Int) -> Int = "moonbitlang_async_getsockerr"

///|
fn check_socket_err(sock : Int) -> Unit raise {
  let err = get_socket_err(sock)
  if err < 0 {
    @os_error.check_errno()
  } else if err > 0 {
    raise @os_error.OSError(err)
  }
}

///|
extern "C" fn enable_keepalive_ffi(
  sock : Int,
  keep_idle : Int,
  keep_count : Int,
  keep_intv : Int,
) -> Int = "moonbitlang_async_enable_keepalive"

///|
#borrow(buf, addr_buf)
extern "C" fn recvfrom_ffi(
  sock : Int,
  buf : FixedArray[Byte],
  offset : Int,
  max_len : Int,
  addr_buf : IpAddr,
) -> Int = "moonbitlang_async_recvfrom"

///|
#borrow(buf, addr_buf)
extern "C" fn sendto_ffi(
  sock : Int,
  buf : Bytes,
  offset : Int,
  max_len : Int,
  addr_buf : IpAddr,
) -> Int = "moonbitlang_async_sendto"
