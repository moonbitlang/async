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
pub fn TCPServer::new(addr : Addr) -> TCPServer raise {
  let sock = make_tcp_socket()
  if 0 != bind_ffi(sock, addr) {
    @fd_util.close(sock)
    @os_error.check_errno()
  }
  if 0 != listen_ffi(sock) {
    @fd_util.close(sock)
    @os_error.check_errno()
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
pub async fn TCPServer::accept(self : TCPServer) -> (TCP, Addr) raise {
  let TCPServer(listen_sock) = self
  let addr = Addr::new(0, 0)
  let conn = @event_loop.perform_job(Accept(sock=listen_sock, addr=addr.0))
  if disable_nagle(conn) < 0 {
    @fd_util.close(conn)
    @os_error.check_errno()
  }
  @fd_util.set_cloexec(conn)
  @fd_util.set_nonblocking(conn)
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
    @os_error.check_errno()
  }
}

///|
/// Make connection to a remote address using `connect(2)` system call.
pub async fn TCP::connect(addr : Addr) -> TCP raise {
  let sock = make_tcp_socket()
  if disable_nagle(sock) < 0 {
    @fd_util.close(sock)
    @os_error.check_errno()
  }
  try @event_loop.perform_job(Connect(sock~, addr=addr.0)) catch {
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
  )
}

///|
pub impl @io.Writer for TCP with write_once(self, buf, offset~, len~) {
  let TCP(sock) = self
  @event_loop.perform_job(Write(fd=sock, buf~, offset~, len~, can_poll=true))
}
