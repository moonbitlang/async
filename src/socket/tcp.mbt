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
/// A Tcp connection
struct Tcp(@event_loop.IOHandle)

///|
#deprecated("use `Tcp` instead")
pub typealias Tcp as TCP

///|
pub fn Tcp::close(self : Tcp) -> Unit {
  let Tcp(sock) = self
  sock.close()
}

///|
struct TcpServer(@event_loop.IOHandle)

///|
#deprecated("use `TcpServer` instead")
pub typealias TcpServer as TCPServer

///|
/// Create a TCP server that is bound to `addr`,
/// listening for incoming connections.
///
/// If `addr` is the IPv6 wildcard address `[::]`
/// and `dual_stack` is `true` (`true` by default),
/// the server will work in dual stack mode,
/// accepting connections from both IPv4 clients and IPv6 clients.
/// The address of IPv4 clients are represented via IPv4-mapped IPv6 address.
///
/// If `addr` is not `[::]`, `dual_stack` is ignored.
pub fn TcpServer::new(
  addr : Addr,
  dual_stack? : Bool = true,
) -> TcpServer raise {
  let context = "@socket.TcpServer::new()"
  let sock = if addr.is_ipv6() {
    make_tcp_socket_ipv6(context)
  } else {
    make_tcp_socket(context)
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
  if 0 != listen_ffi(sock) {
    @fd_util.close(sock, context~)
    @os_error.check_errno(context)
  }
  TcpServer(@event_loop.IOHandle::from_fd(sock, kind=Socket))
}

///|
/// Start the main loop of a TCP server,
/// keep listening for new connections
/// and handle connections using the callback `f`.
/// `f` will be supplied the new connection and the address of the client.
///
/// The client connection will be closed automatically after `f` exits,
/// so `f` must not close the client connection.
/// The server will be automatically closed if `run_forever` fails.
///
/// If `allow_failure` is `true` (`true` by default),
/// failure in `f` will be silently ignored.
///
/// If `max_connections` is present,
/// at most `max_connections` clients are allowed in parallel.
/// New clients will only get handled after a previous client terminates.
pub async fn TcpServer::run_forever(
  self : TcpServer,
  f : async (Tcp, Addr) -> Unit,
  allow_failure? : Bool = true,
  max_connections? : Int,
) -> Unit {
  defer self.close()
  let conn_limit = match max_connections {
    None => None
    Some(n) => Some(@semaphore.Semaphore::new(n))
  }
  @async.with_task_group(fn(group) {
    for {
      let (conn, addr) = self.accept()
      if conn_limit is Some(limit) {
        limit.acquire()
      }
      group.spawn_bg(allow_failure~, fn() {
        defer conn.close()
        if conn_limit is Some(limit) {
          defer limit.release()
          f(conn, addr)
        } else {
          f(conn, addr)
        }
      })
    }
  })
}

///|
pub fn TcpServer::close(self : TcpServer) -> Unit {
  let TcpServer(sock) = self
  sock.close()
}

///|
/// Accept a new connection on a listening TCP server.
/// The accepted connection will be returned together with the address of peer.
pub async fn TcpServer::accept(self : TcpServer) -> (Tcp, Addr) {
  let TcpServer(listen_sock) = self
  // Create a big enough Addr to hold both IPv4 and IPv6 address
  let addr = Addr::empty()
  let conn = listen_sock.accept(addr.0, context="@socket.TcpServer::accept")
  if disable_nagle(conn.fd()) < 0 {
    @fd_util.close(conn.fd(), context="@socket.TcpServer::accept()")
    @os_error.check_errno("@socket.TcpServer::accept(): set TCP_NODELAY")
  }
  @fd_util.set_cloexec(conn.fd(), context="@socket.TcpServer::accept()")
  @fd_util.set_nonblocking(conn.fd(), context="@socket.TcpServer::accept()")
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
pub fn Tcp::enable_keepalive(
  self : Tcp,
  idle_before_keep_alive? : Int = -1,
  keep_alive_count? : Int = -1,
  keep_alive_interval? : Int = -1,
) -> Unit raise {
  let Tcp(sock) = self
  let ret = enable_keepalive_ffi(
    sock.fd(),
    idle_before_keep_alive,
    keep_alive_count,
    keep_alive_interval,
  )
  if ret < 0 {
    @os_error.check_errno("@socket.Tcp::enable_keepalive()")
  }
}

///|
/// Make connection to a remote address using `connect(2)` system call.
pub async fn Tcp::connect(addr : Addr) -> Tcp {
  let context = "@socket.Tcp::connect()"
  let sock = if addr.is_ipv6() {
    make_tcp_socket_ipv6(context)
  } else {
    make_tcp_socket(context)
  }
  if disable_nagle(sock) < 0 {
    @fd_util.close(sock, context~)
    @os_error.check_errno("@socket.Tcp::connect(): set TCP_NODELAY")
  }
  let conn = @event_loop.IOHandle::from_fd(sock, kind=Socket)
  try conn.connect(addr.0, context~) catch {
    err => {
      conn.close()
      raise err
    }
  } noraise {
    _ => Tcp(conn)
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
pub impl @io.Reader for Tcp with read(
  self,
  buf,
  offset? = 0,
  max_len? = buf.length() - offset,
) {
  let Tcp(sock) = self
  sock.read(buf, offset~, len=max_len, context="@socket.Tcp::read()")
}

///|
pub impl @io.Writer for Tcp with write_once(self, buf, offset~, len~) {
  let Tcp(sock) = self
  sock.write(buf, offset~, len~, context="@socket.Tcp::write()")
}
