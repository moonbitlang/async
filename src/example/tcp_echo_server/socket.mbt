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
extern "C" fn bind_ffi(sock : Int, ip : UInt, port : Int) -> Int = "bind_ffi"

///|
fn bind(sock : Int, ip : String, port : Int) -> Unit raise {
  guard ip.split(".").map(_.to_string()).collect().map(@strconv.parse_uint(_))
    is [a, b, c, d]
  let ip = (a << 24) | (b << 16) | (c << 8) | d
  if 0 != bind_ffi(sock, ip, port) {
    @os_error.check_errno()
  }
}

///|
extern "C" fn listen_ffi(sock : Int) -> Int = "listen_ffi"

///|
fn listen(sock : Int) -> Unit raise {
  if 0 != listen_ffi(sock) {
    @os_error.check_errno()
  }
}

///|
extern "C" fn accept_ffi(sock : Int) -> Int = "accept_ffi"

///|
async fn accept(sock : Int) -> Int raise {
  @async.wait_fd(sock)
  let sock = accept_ffi(sock)
  if sock < 0 {
    @os_error.check_errno()
  }
  sock
}

///|
#borrow(buf)
extern "C" fn recv_ffi(sock : Int, buf : Bytes, bufsize : Int) -> Int = "recv_ffi"

///|
async fn recv(sock : Int, buf : Bytes) -> Int raise {
  @async.wait_fd(sock)
  let n = recv_ffi(sock, buf, buf.length())
  if n < 0 {
    @os_error.check_errno()
  }
  n
}

///|
#borrow(buf)
extern "C" fn send_ffi(sock : Int, buf : Bytes, bufsize : Int) -> Int = "send_ffi"

///|
fn send(sock : Int, buf : Bytes) -> Int raise {
  let n = send_ffi(sock, buf, buf.length())
  if n < 0 {
    @os_error.check_errno()
  }
  n
}
