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
type UDP Int

///|
pub fn UDP::new() -> UDP {
  make_udp_socket()
}

///|
pub fn UDP::close(self : UDP) -> Unit {
  let UDP(sock) = self
  @async.close(sock)
}

///|
pub fn UDP::bind(self : UDP, addr : Addr) -> Unit raise {
  let UDP(sock) = self
  if 0 != bind_ffi(sock, addr) {
    @os_error.check_errno()
  }
}

///|
pub fn UDP::connect(self : UDP, addr : Addr) -> Unit raise {
  let UDP(sock) = self
  if 0 != connect_ffi(sock, addr) {
    @os_error.check_errno()
  }
}

///|
pub async fn UDP::recv(
  self : UDP,
  buf : FixedArray[Byte],
  offset~ : Int = 0,
  max_len? : Int,
) -> Int raise {
  let max_len = max_len.unwrap_or(buf.length() - offset)
  let UDP(sock) = self
  let n_read = recv_ffi(sock, buf, offset, max_len)
  if n_read > 0 {
    return n_read
  } else if @os_error.is_nonblocking_io_error() {
    @async.wait_fd_read(sock)
    recv_ffi(sock, buf, offset, max_len)
  } else {
    @os_error.check_errno()
    n_read
  }
}

///|
pub async fn UDP::recvfrom(
  self : UDP,
  buf : FixedArray[Byte],
  offset~ : Int = 0,
  max_len? : Int,
) -> (Int, Addr) raise {
  let max_len = max_len.unwrap_or(buf.length() - offset)
  let UDP(sock) = self
  let addr = Addr::new(0, 0)
  let n_read = recvfrom_ffi(sock, buf, offset, max_len, addr)
  let n_read = if n_read < 0 && @os_error.is_nonblocking_io_error() {
    @async.wait_fd_read(sock)
    recvfrom_ffi(sock, buf, offset, max_len, addr)
  } else {
    n_read
  }
  if n_read < 0 {
    @os_error.check_errno()
  }
  (n_read, addr)
}

///|
pub async fn UDP::send(
  self : UDP,
  buf : Bytes,
  offset~ : Int = 0,
  len? : Int,
) -> Unit raise {
  let len = len.unwrap_or(buf.length() - offset)
  let UDP(sock) = self
  for {
    let n_sent = send_ffi(sock, buf, offset, len)
    if n_sent > 0 {
      return
    }
    if @os_error.is_nonblocking_io_error() {
      @async.wait_fd_write(sock)
    } else {
      @os_error.check_errno()
    }
  }
}

///|
pub async fn UDP::sendto(
  self : UDP,
  buf : Bytes,
  addr : Addr,
  offset~ : Int = 0,
  len? : Int,
) -> Unit raise {
  let len = len.unwrap_or(buf.length() - offset)
  let UDP(sock) = self
  for {
    let n_sent = sendto_ffi(sock, buf, offset, len, addr)
    if n_sent > 0 {
      return
    }
    if @os_error.is_nonblocking_io_error() {
      @async.wait_fd_write(sock)
    } else {
      @os_error.check_errno()
    }
  }
}
