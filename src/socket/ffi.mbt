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
extern "C" fn make_tcp_socket_ffi(family : AddrFamily) -> Int = "moonbitlang_async_make_tcp_socket"

///|
fn make_tcp_socket(family : AddrFamily, context~ : String) -> Int raise {
  let sock = make_tcp_socket_ffi(family)
  if sock < 0 {
    @os_error.check_errno(context)
  }
  @fd_util.set_cloexec(sock, context~)
  @fd_util.set_nonblocking(sock, context~)
  sock
}

///|
extern "C" fn make_udp_socket_ffi(family : AddrFamily) -> Int = "moonbitlang_async_make_udp_socket"

///|
fn make_udp_socket(family : AddrFamily, context~ : String) -> Int raise {
  let sock = make_udp_socket_ffi(family)
  if sock < 0 {
    @os_error.check_errno(context)
  }
  @fd_util.set_cloexec(sock, context~)
  @fd_util.set_nonblocking(sock, context~)
  sock
}

///|
#borrow(addr)
extern "C" fn bind_ffi(sock : Int, addr : Addr) -> Int = "moonbitlang_async_bind"

///|
extern "C" fn set_ipv6_only(sock : Int, dual_stack : Bool) -> Int = "moonbitlang_async_set_ipv6_only"

///|
extern "C" fn listen_ffi(sock : Int) -> Int = "moonbitlang_async_listen"

///|
#borrow(addr)
extern "C" fn connect_ffi(sock : Int, addr : Addr) -> Int = "moonbitlang_async_connect"

///|
extern "C" fn disable_nagle(sock : Int) -> Int = "moonbitlang_async_disable_nagle"

///|
extern "C" fn enable_keepalive_ffi(
  sock : Int,
  keep_idle : Int,
  keep_count : Int,
  keep_intv : Int,
) -> Int = "moonbitlang_async_enable_keepalive"
