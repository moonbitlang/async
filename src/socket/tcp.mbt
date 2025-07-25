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
/// A TCP socket directly corresponding to OS socket.
type TCP Int

///|
/// Create a new TCP socket using the `socket(2)` system call.
/// The created socket always operate in non-blocking mode.
pub fn TCP::new() -> TCP {
  make_tcp_socket()
}

///|
pub fn TCP::close(self : TCP) -> Unit {
  let TCP(sock) = self
  @event_loop.close_fd(sock)
}

///|
/// Bind the socket to an address using the `bind(2)` system call.
pub fn TCP::bind(self : TCP, addr : Addr) -> Unit raise {
  let TCP(sock) = self
  if 0 != bind_ffi(sock, addr) {
    @os_error.check_errno()
  }
}

///|
/// Turn the socket into listen mode using `listen(2)` system call,
/// so that it can start accepting connections.
pub fn TCP::listen(self : TCP) -> Unit raise {
  let TCP(sock) = self
  if 0 != listen_ffi(sock) {
    @os_error.check_errno()
  }
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
  idle_before_keep_alive~ : Int = -1,
  keep_alive_count~ : Int = -1,
  keep_alive_interval~ : Int = -1,
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
/// Accept a new connection on a listening socket using `accept(2)` system call.
/// A new socket representing the accepted connection
/// will be returned together with the address of peer.
pub async fn TCP::accept(self : TCP) -> (TCP, Addr) raise {
  let TCP(listen_sock) = self
  @event_loop.prepare_fd_read(listen_sock)
  let addr = Addr::new(0, 0)
  for {
    let conn_sock = accept_ffi(listen_sock, addr)
    if conn_sock > 0 {
      return (TCP(conn_sock), addr)
    } else if @os_error.is_nonblocking_io_error() {
      @event_loop.wait_fd_read(listen_sock)
    } else {
      @os_error.check_errno()
    }
  }
}

///|
/// Make connection to a remote address using `connect(2)` system call.
pub async fn TCP::connect(self : TCP, addr : Addr) -> Unit raise {
  let TCP(sock) = self
  @event_loop.prepare_fd_write(sock)
  if 0 == connect_ffi(sock, addr) {
    return
  }
  if @os_error.is_nonblocking_io_error() {
    @event_loop.wait_fd_write(sock)
    check_socket_err(sock)
  } else {
    @os_error.check_errno()
  }
}

///|
/// Receive data from a TCP connection using `recv(2)` system call.
/// For `tcp.recv(buf, offset~, max_len~)`,
/// at most `max_len` bytes of data will be written to `buf`, starting from `offset`.
/// The number of received bytes will be returned.
///
/// At most one task can read from a TCP socket at any time.
/// To allow multiple reader,
/// use a worker task for reading and use `@async.Queue` to distribute the data.
pub async fn TCP::recv(
  self : TCP,
  buf : FixedArray[Byte],
  offset~ : Int = 0,
  max_len? : Int,
) -> Int raise {
  let max_len = max_len.unwrap_or(buf.length() - offset)
  let TCP(sock) = self
  @event_loop.prepare_fd_read(sock)
  let n_read = recv_ffi(sock, buf, offset, max_len)
  let n_read = if n_read < 0 && @os_error.is_nonblocking_io_error() {
    @event_loop.wait_fd_read(sock)
    recv_ffi(sock, buf, offset, max_len)
  } else {
    @async.pause()
    n_read
  }
  if n_read < 0 {
    @os_error.check_errno()
  }
  n_read
}

///|
pub suberror ConnectionClosed derive(Show)

///|
/// `conn.recv_exactly(n)` receives exactly `n` bytes of data from a TCP connection.
/// `recv_exactly` will only return after all `n` bytes of data are received.
/// If the connection is closed before receiving all data, an error is raised.
///
/// At most one task can read from a TCP socket at any time.
/// To allow multiple reader,
/// use a worker task for reading and use `@async.Queue` to distribute the data.
pub async fn TCP::recv_exactly(self : TCP, len : Int) -> Bytes raise {
  let buf = FixedArray::make(len, (0 : Byte))
  for received = 0; received < len; {
    let new_received = self.recv(buf, offset=received, max_len=len - received)
    if new_received == 0 {
      raise ConnectionClosed
    }
    continue received + new_received
  }
  buf.unsafe_reinterpret_as_bytes()
}

///|
/// Send data through a TCP connection using `send(2)` system call.
/// This function will only return after all data have been successfully sent.
///
/// At most one task can write to a TCP socket at any time.
/// To allow multiple writers,
/// use a worker task for writing and use `@async.Queue` to gather data.
pub async fn TCP::send(
  self : TCP,
  buf : Bytes,
  offset~ : Int = 0,
  len? : Int,
) -> Unit raise {
  let len = len.unwrap_or(buf.length() - offset)
  let TCP(sock) = self
  @event_loop.prepare_fd_write(sock)
  for sent = 0; sent < len; {
    let new_sent = send_ffi(sock, buf, offset + sent, len - sent)
    if new_sent < 0 {
      if @os_error.is_nonblocking_io_error() {
        @event_loop.wait_fd_write(sock)
      } else {
        @os_error.check_errno()
      }
    } else {
      continue sent + new_sent
    }
  }
}
