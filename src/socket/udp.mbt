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
struct UDP(Int)

///|
/// Create a new UDP socket using the `socket(2)` system call.
/// The created socket always operate in non-blocking mode.
pub fn UDP::new() -> UDP raise {
  let sock = make_udp_socket()
  if sock < 0 {
    @os_error.check_errno("@socket.UDP::new()")
  }
  @fd_util.set_cloexec(sock, context="@socket.UDP::new()")
  @fd_util.set_nonblocking(sock, context="@socket.UDP::new()")
  UDP(sock)
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
  let bind_result = if addr.is_ipv6() {
    bind_ipv6_ffi(sock, addr)
  } else {
    bind_ffi(sock, addr)
  }
  if 0 != bind_result {
    @os_error.check_errno("@socket.UDP::bind()")
  }
}

///|
/// "connect" the socket to remote address using `connect(2)` system call.
/// For UDP socket, connect means setting the default address for `send`.
pub fn UDP::connect(self : UDP, addr : Addr) -> Unit raise {
  let UDP(sock) = self
  let connect_result = if addr.is_ipv6() {
    connect_ipv6_ffi(sock, addr)
  } else {
    connect_ffi(sock, addr)
  }
  if 0 != connect_result {
    @os_error.check_errno("@socket.UDP::connect()")
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
///
/// At most one task can read from a UDP socket at any time.
/// To allow multiple reader,
/// use a worker task for reading and use `@async.Queue` to distribute the data.
pub async fn UDP::recv(
  self : UDP,
  buf : FixedArray[Byte],
  offset? : Int = 0,
  max_len? : Int = buf.length() - offset,
) -> Int {
  let UDP(sock) = self
  @event_loop.perform_job(
    Read(fd=sock, buf~, offset~, len=max_len, can_poll=true),
    context="@socket.UDP::recv",
  )
}

///|
/// Same as `UDP::recv`, but also return the address of sender.
/// Receive packet from a UDP socket  using `recvfrom(2)` system call.
/// For `udp.recv(buf, offset~, max_len~)`,
/// at most `max_len` bytes of data will be written to `buf`, starting from `offset`.
/// The number of received bytes and the source address of the packet will be returned.
///
/// UDP is a datagram based protocol,
/// and `recv` will always receive exactly one UDP packet.
/// If the buffer is smaller than the received packet,
/// the rest of the packet will be lost.
///
/// At most one task can read from a UDP socket at any time.
/// To allow multiple reader,
/// use a worker task for reading and use `@async.Queue` to distribute the data.
pub async fn UDP::recvfrom(
  self : UDP,
  buf : FixedArray[Byte],
  offset? : Int = 0,
  max_len? : Int = buf.length() - offset,
) -> (Int, Addr) {
  let UDP(sock) = self
  // Create a big enough Addr to hold both IPv4 and IPv6 address
  let addr = Addr::empty()
  let n_read = @event_loop.perform_job(
    Recvfrom(sock~, buf~, offset~, len=max_len, addr=addr.0),
    context="@socket.UDP::recvfrom",
  )
  (n_read, addr)
}

///|
/// Send data through a UDP socket using `send(2)` system call.
/// The address of the remote peer is determined by `bind` or `connect`.
///
/// UDP is a datagram based protocol, every call of `send` will send exactly one packet.
///
/// At most one task can write to a UDP socket at any time.
/// To allow multiple writers,
/// use a worker task for reading and use `@async.Queue` to gather the data.
pub async fn UDP::send(
  self : UDP,
  buf : Bytes,
  offset? : Int = 0,
  len? : Int = buf.length() - offset,
) -> Unit {
  let UDP(sock) = self
  @event_loop.perform_job(
    Write(fd=sock, buf~, offset~, len~, can_poll=true),
    context="@socket.UDP::send",
  )
  |> ignore
}

///|
/// Same as `send`, but the address to send is explicitly passed as argument.
/// Send data through a UDP socket using `sendto(2)` system call.
/// The address of the remote peer is determined by `bind` or `connect`.
///
/// UDP is a datagram based protocol, every call of `send` will send exactly one packet.
///
/// At most one task can write to a UDP socket at any time.
/// To allow multiple writers,
/// use a worker task for reading and use `@async.Queue` to gather the data.
pub async fn UDP::sendto(
  self : UDP,
  buf : Bytes,
  addr : Addr,
  offset? : Int = 0,
  len? : Int = buf.length() - offset,
) -> Unit {
  let UDP(sock) = self
  @event_loop.perform_job(
    Sendto(sock~, buf~, offset~, len~, addr=addr.0),
    context="@socket.UDP::sendto",
  )
  |> ignore
}
