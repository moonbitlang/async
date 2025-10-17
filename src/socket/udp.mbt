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
/// A UDP client "connected" to a remote UDP server.
///
/// UDP is a connectionless protocol, here "connected" means
/// the client always send packet to and receive packet from
/// the specified remote server.
struct UdpClient(Int)

///|
/// Create a new UDP client connected to server at `addr`.
/// The client always send packet to and receive packet from
/// the specified remote server.
pub fn UdpClient::new(server : Addr) -> UdpClient raise {
  let context = "@socket.UdpClient::new()"
  let sock = if server.is_ipv6() {
    make_udp_socket_ipv6(context)
  } else {
    make_udp_socket(context)
  }
  let connect_result = if server.is_ipv6() {
    connect_ipv6_ffi(sock, server)
  } else {
    connect_ffi(sock, server)
  }
  if 0 != connect_result {
    @fd_util.close(sock, context~)
    @os_error.check_errno(context)
  }
  UdpClient(sock)
}

///|
pub fn UdpClient::close(self : UdpClient) -> Unit {
  let UdpClient(sock) = self
  @event_loop.close_fd(sock)
}

///|
/// A UDP server bound to a listen address and receive packets from clients.
struct UdpServer(Int)

///|
pub fn UdpServer::close(self : UdpServer) -> Unit {
  let UdpServer(sock) = self
  @event_loop.close_fd(sock)
}

///|
/// Create a UDP server listening at `addr`.
///
/// If `addr` is the IPv6 wildcard address `[::]`
/// and `dual_stack` is `true` (`true` by default),
/// the server will work in dual stack mode,
/// receiving packets from both IPv4 peers and IPv6 peers.
/// The address of IPv4 peers are represented via IPv4-mapped IPv6 address.
///
/// If `addr` is not `[::]`, `dual_stack` is ignored.
pub fn UdpServer::new(
  addr : Addr,
  dual_stack? : Bool = true,
) -> UdpServer raise {
  let context = "@socket.UdpServer::new()"
  let sock = if addr.is_ipv6() {
    make_udp_socket_ipv6(context)
  } else {
    make_udp_socket(context)
  }
  if addr.is_ipv6() && addr.is_ipv6_wildcard() {
    if 0 != set_ipv6_only(sock, !dual_stack) {
      @fd_util.close(sock, context~)
      @os_error.check_errno(context)
    }
  }
  let bind_result = if addr.is_ipv6() {
    bind_ipv6_ffi(sock, addr)
  } else {
    bind_ffi(sock, addr)
  }
  if bind_result != 0 {
    @fd_util.close(sock, context~)
    @os_error.check_errno(context)
  }
  UdpServer(sock)
}

///|
/// Receive packet from a UDP client.
/// For `udp.recv(buf, offset~, max_len~)`,
/// at most `max_len` bytes of data will be written to `buf`, starting from `offset`.
/// The number of received bytes will be returned.
///
/// UDP is a datagram based protocol,
/// and `recv` will always receive exactly one UDP packet.
/// If the buffer is smaller than the received packet,
/// the rest of the packet will be lost.
///
/// At most one task can read from a UDP client at any time.
/// To allow multiple reader,
/// use a worker task for reading and use `@async.Queue` to distribute the data.
pub async fn UdpClient::recv(
  self : UdpClient,
  buf : FixedArray[Byte],
  offset? : Int = 0,
  max_len? : Int = buf.length() - offset,
) -> Int {
  let UdpClient(sock) = self
  @event_loop.read(
    sock,
    buf,
    offset~,
    len=max_len,
    can_poll=true,
    context="@socket.UdpClient::recv",
  )
}

///|
/// Receive packet from a UDP server, and obtain the source address of the packet.
/// For `udp.recvfrom(buf, offset~, max_len~)`,
/// at most `max_len` bytes of data will be written to `buf`, starting from `offset`.
/// The number of received bytes and the source address of the packet will be returned.
///
/// UDP is a datagram based protocol,
/// and `recv` will always receive exactly one UDP packet.
/// If the buffer is smaller than the received packet,
/// the rest of the packet will be lost.
///
/// At most one task can read from a UDP server at any time.
/// To allow multiple reader,
/// use a worker task for reading and use `@async.Queue` to distribute the data.
pub async fn UdpServer::recvfrom(
  self : UdpServer,
  buf : FixedArray[Byte],
  offset? : Int = 0,
  max_len? : Int = buf.length() - offset,
) -> (Int, Addr) {
  let UdpServer(sock) = self
  // Create a big enough Addr to hold both IPv4 and IPv6 address
  let addr = Addr::empty()
  let n_read = @event_loop.recvfrom(
    sock,
    buf,
    offset~,
    len=max_len,
    addr=addr.0,
    context="@socket.UdpServer::recvfrom",
  )
  (n_read, addr)
}

///|
/// Send data through a UDP client.
///
/// UDP is a datagram based protocol, every call of `send` will send exactly one packet.
///
/// At most one task can write to a UDP client at any time.
/// To allow multiple writers,
/// use a worker task for reading and use `@async.Queue` to gather the data.
pub async fn UdpClient::send(
  self : UdpClient,
  buf : Bytes,
  offset? : Int = 0,
  len? : Int = buf.length() - offset,
) -> Unit {
  let UdpClient(sock) = self
  @event_loop.write(
    sock,
    buf,
    offset~,
    len~,
    can_poll=true,
    context="@socket.UdpClient::send",
  )
  |> ignore
}

///|
/// Send a packet to `addr` through a UDP server.
///
/// UDP is a datagram based protocol, every call of `send` will send exactly one packet.
///
/// At most one task can write to a UDP server at any time.
/// To allow multiple writers,
/// use a worker task for reading and use `@async.Queue` to gather the data.
pub async fn UdpServer::sendto(
  self : UdpServer,
  buf : Bytes,
  addr : Addr,
  offset? : Int = 0,
  len? : Int = buf.length() - offset,
) -> Unit {
  let UdpServer(sock) = self
  @event_loop.sendto(
    sock,
    buf,
    offset~,
    len~,
    addr=addr.0,
    context="@socket.UdpServer::sendto",
  )
  |> ignore
}
