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
/// A TCP connection
struct TCP(Int)

///|
pub fn TCP::close(self : TCP) -> Unit {
  let TCP(sock) = self
  @event_loop.close_fd(sock)
}

///|
struct TCPServer(Int)

///|
/// Create a TCP server that is bound to `addr`,
/// listening for incoming connections.
///
/// If `addr` is an IPv6 (including the wildcard address `[::]`),
/// the server will be IPv6 only.
/// For dual stack server, see `@socket.TCPServer::new_dual_stack`.
pub fn TCPServer::new(addr : Addr) -> TCPServer raise {
  let context = "@socket.TCPServer::new()"
  let sock = if addr.is_ipv6() {
    make_tcp_socket_ipv6(context)
  } else {
    make_tcp_socket(context)
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
  if 0 != listen_ffi(sock) {
    @fd_util.close(sock, context~)
    @os_error.check_errno(context)
  }
  TCPServer(sock)
}

///|
/// Create a dual stack TCP server that listen for connections
/// from all IPv4 and IPv6 clients at `port`.
/// The address of IPv4 clients are represented via IPv4-mapped IPv6 address.
pub fn TCPServer::new_dual_stack(port : Int) -> TCPServer raise {
  let context = "@socket.TCPServer::new_dual_stack()"
  let sock = make_tcp_socket_ipv6(context)
  if bind_dual_stack(sock, port) != 0 {
    @fd_util.close(sock, context~)
    @os_error.check_errno(context)
  }
  if 0 != listen_ffi(sock) {
    @fd_util.close(sock, context~)
    @os_error.check_errno(context)
  }
  TCPServer(sock)
}

///|
pub fn TCPServer::close(self : TCPServer) -> Unit {
  let TCPServer(sock) = self
  @event_loop.close_fd(sock)
}

///|
/// Accept a new connection on a listening TCP server.
/// The accepted connection will be returned together with the address of peer.
pub async fn TCPServer::accept(self : TCPServer) -> (TCP, Addr) {
  let TCPServer(listen_sock) = self
  // Create a big enough Addr to hold both IPv4 and IPv6 address
  let addr = Addr::empty()
  let conn = @event_loop.perform_job(
    Accept(sock=listen_sock, addr=addr.0),
    context="@socket.TCPServer::accept",
  )
  if disable_nagle(conn) < 0 {
    @fd_util.close(conn, context="@socket.TCPServer::accept()")
    @os_error.check_errno("@socket.TCPServer::accept(): set TCP_NODELAY")
  }
  @fd_util.set_cloexec(conn, context="@socket.TCPServer::accept()")
  @fd_util.set_nonblocking(conn, context="@socket.TCPServer::accept()")
  (conn, addr)
}

///|
/// Enable TCP keep alive on the socket.
///
/// `idle_before_keep_alive` is the duration of idle time in seconds to wait
/// before sending the first keep alive probe.
///
/// `keep_alive_count` is the number of keep alive probe to try
/// before closing the connection.
///
/// `keep_alive_interval` is the time in seconds between two keep alive probes.
pub fn TCP::enable_keepalive(
  self : TCP,
  idle_before_keep_alive? : Int = -1,
  keep_alive_count? : Int = -1,
  keep_alive_interval? : Int = -1,
) -> Unit raise {
  let TCP(sock) = self
  let ret = enable_keepalive_ffi(
    sock, idle_before_keep_alive, keep_alive_count, keep_alive_interval,
  )
  if ret < 0 {
    @os_error.check_errno("@socket.TCP::enable_keepalive()")
  }
}

///|
/// Make connection to a remote address using `connect(2)` system call.
pub async fn TCP::connect(addr : Addr) -> TCP {
  let sock = if addr.is_ipv6() {
    make_tcp_socket_ipv6("@socket.TCP::connect()")
  } else {
    make_tcp_socket("@socket.TCP::connect()")
  }
  if disable_nagle(sock) < 0 {
    @fd_util.close(sock, context="@socket.TCP::connect()")
    @os_error.check_errno("@socket.TCP::connect(): set TCP_NODELAY")
  }
  try
    @event_loop.perform_job(
      Connect(sock~, addr=addr.0),
      context="@socket.TCP::connect",
    )
  catch {
    err => {
      @event_loop.close_fd(sock)
      raise err
    }
  } noraise {
    _ => TCP(sock)
  }
}

///|
/// Receive data from a TCP connection.
/// For `tcp.recv(buf, offset~, max_len~)`,
/// at most `max_len` bytes of data will be written to `buf`, starting from `offset`.
/// The number of received bytes will be returned.
///
/// At most one task can read from a TCP socket at any time.
/// To allow multiple reader,
/// use a worker task for reading and use `@async.Queue` to distribute the data.
pub impl @io.Reader for TCP with read(
  self,
  buf,
  offset? = 0,
  max_len? = buf.length() - offset,
) {
  let TCP(sock) = self
  @event_loop.perform_job(
    Read(fd=sock, buf~, offset~, len=max_len, can_poll=true),
    context="@socket.TCP::read",
  )
}

///|
pub impl @io.Writer for TCP with write_once(self, buf, offset~, len~) {
  let TCP(sock) = self
  @event_loop.perform_job(
    Write(fd=sock, buf~, offset~, len~, can_poll=true),
    context="@socket.TCP::write",
  )
}
