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
/// A UDP socket directly corresponding to OS socket
type UDP Int

///|
/// Create a new UDP socket using the `socket(2)` system call.
/// The created socket always operate in non-blocking mode.
pub fn UDP::new() -> UDP {
  make_udp_socket()
}

///|
pub fn UDP::close(self : UDP) -> Unit {
  let UDP(sock) = self
  @event_loop.close_fd(sock)
}

///|
/// Bind the socket to an address using the `bind(2)` system call,
/// so that the socket can be used to receive packets from the address.
pub fn UDP::bind(self : UDP, addr : Addr) -> Unit raise {
  let UDP(sock) = self
  if 0 != bind_ffi(sock, addr) {
    @os_error.check_errno()
  }
}

///|
/// "connect" the socket to remote address using `connect(2)` system call.
/// For UDP socket, connect means setting the default address for `send`.
pub fn UDP::connect(self : UDP, addr : Addr) -> Unit raise {
  let UDP(sock) = self
  if 0 != connect_ffi(sock, addr) {
    @os_error.check_errno()
  }
}

///|
/// Receive packet from a UDP socket  using `recv(2)` system call.
/// For `udp.recv(buf, offset~, max_len~)`,
/// at most `max_len` bytes of data will be written to `buf`, starting from `offset`.
/// The number of received bytes will be returned.
///
/// UDP is a datagram based protocol,
/// and `recv` will always receive exactly one UDP packet.
/// If the buffer is smaller than the received packet,
/// the rest of the packet will be lost.
pub async fn UDP::recv(
  self : UDP,
  buf : FixedArray[Byte],
  offset~ : Int = 0,
  max_len? : Int,
) -> Int raise {
  let max_len = max_len.unwrap_or(buf.length() - offset)
  let UDP(sock) = self
  @event_loop.prepare_fd_read(sock)
  let n_read = recv_ffi(sock, buf, offset, max_len)
  if n_read > 0 {
    return n_read
  } else if @os_error.is_nonblocking_io_error() {
    @event_loop.wait_fd_read(sock)
    recv_ffi(sock, buf, offset, max_len)
  } else {
    @os_error.check_errno()
    n_read
  }
}

///|
/// Same as `UDP::recv`, but also return the address of sender.
pub async fn UDP::recvfrom(
  self : UDP,
  buf : FixedArray[Byte],
  offset~ : Int = 0,
  max_len? : Int,
) -> (Int, Addr) raise {
  let max_len = max_len.unwrap_or(buf.length() - offset)
  let UDP(sock) = self
  @event_loop.prepare_fd_read(sock)
  let addr = Addr::new(0, 0)
  let n_read = recvfrom_ffi(sock, buf, offset, max_len, addr)
  let n_read = if n_read < 0 && @os_error.is_nonblocking_io_error() {
    @event_loop.wait_fd_read(sock)
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
/// Send data through a UDP socket using `send(2)` system call.
/// The address of the remote peer is determined by `bind` or `connect`.
///
/// UDP is a datagram based protocol, every call of `send` will send exactly one packet.
pub async fn UDP::send(
  self : UDP,
  buf : Bytes,
  offset~ : Int = 0,
  len? : Int,
) -> Unit raise {
  let len = len.unwrap_or(buf.length() - offset)
  let UDP(sock) = self
  @event_loop.prepare_fd_write(sock)
  for {
    let n_sent = send_ffi(sock, buf, offset, len)
    if n_sent > 0 {
      return
    }
    if @os_error.is_nonblocking_io_error() {
      @event_loop.wait_fd_write(sock)
    } else {
      @os_error.check_errno()
    }
  }
}

///|
/// Same as `send`, but the address to send is explicitly passed as argument.
pub async fn UDP::sendto(
  self : UDP,
  buf : Bytes,
  addr : Addr,
  offset~ : Int = 0,
  len? : Int,
) -> Unit raise {
  let len = len.unwrap_or(buf.length() - offset)
  let UDP(sock) = self
  @event_loop.prepare_fd_write(sock)
  for {
    let n_sent = sendto_ffi(sock, buf, offset, len, addr)
    if n_sent > 0 {
      return
    }
    if @os_error.is_nonblocking_io_error() {
      @event_loop.wait_fd_write(sock)
    } else {
      @os_error.check_errno()
    }
  }
}
