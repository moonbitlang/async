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
type TCP Int

///|
pub fn TCP::new() -> TCP {
  make_tcp_socket()
}

///|
pub fn TCP::close(self : TCP) -> Unit {
  let TCP(sock) = self
  @async.close(sock)
}

///|
pub fn TCP::bind(self : TCP, addr : Addr) -> Unit raise {
  let TCP(sock) = self
  if 0 != bind_ffi(sock, addr) {
    @os_error.check_errno()
  }
}

///|
pub fn TCP::listen(self : TCP) -> Unit raise {
  let TCP(sock) = self
  if 0 != listen_ffi(sock) {
    @os_error.check_errno()
  }
}

///|
pub async fn TCP::accept(self : TCP) -> (TCP, Addr) raise {
  let TCP(listen_sock) = self
  let addr = Addr::new(0, 0)
  for {
    let conn_sock = accept_ffi(listen_sock, addr)
    if conn_sock > 0 {
      return (TCP(conn_sock), addr)
    } else if @os_error.get_errno() is @os_error.EAGAIN {
      @async.wait_fd_read(listen_sock)
    } else {
      @os_error.check_errno()
    }
  }
}

///|
pub async fn TCP::connect(self : TCP, addr : Addr) -> Unit raise {
  let TCP(sock) = self
  if 0 == connect_ffi(sock, addr) {
    return
  }
  if @os_error.is_nonblocking_io_error(@os_error.get_errno()) {
    @async.wait_fd_write(sock)
    check_socket_err(sock)
  } else {
    @os_error.check_errno()
  }
}

///|
pub async fn TCP::recv(
  self : TCP,
  buf : FixedArray[Byte],
  offset~ : Int = 0,
  max_len? : Int,
) -> Int raise {
  let max_len = max_len.unwrap_or(buf.length() - offset)
  let TCP(sock) = self
  @async.wait_fd_read(sock)
  let n_read = recv_ffi(sock, buf, offset, max_len)
  if n_read < 0 {
    @os_error.check_errno()
  }
  n_read
}

///|
pub async fn TCP::send(
  self : TCP,
  buf : Bytes,
  offset~ : Int = 0,
  len? : Int,
) -> Unit raise {
  let len = len.unwrap_or(buf.length() - offset)
  let TCP(sock) = self
  for sent = 0; sent < len; {
    let new_sent = send_ffi(sock, buf, offset + sent, len - sent)
    if new_sent < 0 {
      if @os_error.get_errno() is (@os_error.EAGAIN | @os_error.EWOULDBLOCK) {
        @async.wait_fd_write(sock)
      } else {
        @os_error.check_errno()
      }
    } else {
      continue sent + new_sent
    }
  }
}
