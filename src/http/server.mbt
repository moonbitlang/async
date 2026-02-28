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
priv struct H2ServerState {
  server_conn : @http2.H2ServerConnection
  stream : @http2.H2Stream
  mut response_sent : Bool
}

///|
/// A single HTTP server connection
struct ServerConnection {
  reader : Reader
  conn : @socket.Tcp
  sender : Sender
  mut closed : Bool
  h2 : H2ServerState?
}

///|
/// Create a new HTTP server connection from a TCP connection.
///
/// `headers` can be used to specify persistent headers for the connection,
/// i.e. all response sent by this connection will share these headers.
/// The following headers is automatically set,
/// and must not be specified in `headers`:
/// 
/// - Content-Length, Transfer-Encoding
pub fn ServerConnection::new(
  conn : @socket.Tcp,
  headers? : Map[String, String] = {},
) -> ServerConnection {
  {
    reader: Reader::new(conn),
    conn,
    sender: Sender::new(conn, headers~),
    closed: false,
    h2: None,
  }
}

///|
/// Close the connection, the underlying TCP connection will be closed as well.
/// This function is idempotent: it is safe to call `.close()` multiple times,
/// only the first `.close()` call takes effect.
pub fn ServerConnection::close(self : ServerConnection) -> Unit {
  if !self.closed {
    self.closed = true
    // For H2, don't close the TCP connection (shared across streams)
    if self.h2 is None {
      self.conn.close()
    }
  }
}

///|
/// Get the address of client from a HTTP server connection
pub fn ServerConnection::client_addr(self : ServerConnection) -> @socket.Addr {
  self.conn.addr()
}

///|
pub impl @io.Reader for ServerConnection with _direct_read(
  self,
  buf,
  offset~,
  max_len~,
) {
  if self.h2 is Some(h2) {
    h2.stream._direct_read(buf, offset~, max_len~)
  } else {
    self.reader._direct_read(buf, offset~, max_len~)
  }
}

///|
pub impl @io.Reader for ServerConnection with _get_internal_buffer(self) {
  if self.h2 is Some(h2) {
    h2.stream._get_internal_buffer()
  } else {
    self.reader._get_internal_buffer()
  }
}

///|
/// Read a single request from the connection.
/// If the body of the last request is not consumed yet,
/// it will be discarded.
///
/// After calling `read_request`,
/// the body of the request can be obtained by using `ServerConnection`
/// as a `@io.Reader`.
pub async fn ServerConnection::read_request(self : ServerConnection) -> Request {
  if self.h2 is Some(h2) {
    build_h2_request(h2.stream.wait_headers())
  } else {
    self.reader.skip_body()
    self.reader.read_request()
  }
}

///|
/// Manually discard the body of the request currently being processed.
pub async fn ServerConnection::skip_request_body(
  self : ServerConnection,
) -> Unit {
  if self.h2 is Some(_) {
    while self.drop(1024) == 1024 {

    }
  } else {
    self.reader.skip_body()
  }
}

///|
/// Write data to the body of the response currently being sent.
/// Must be called after `send_response`.
/// `end_response` must be called after all content of response body has been sent.
///
/// Writing to `@http.ServerConnection` MAY be buffered,
/// call `flush` manually to ensure data is delivered to the remote peer.
pub impl @io.Writer for ServerConnection with write_once(
  self,
  buf,
  offset~,
  len~,
) {
  if self.h2 is Some(h2) {
    let data = buf[offset:offset + len].to_bytes()
    h2.stream.send_data(data, end_stream=false)
    len
  } else {
    guard not(self.sender.mode is SendingHeader)
    self.sender.write_once(buf, offset~, len~)
  }
}

///|
pub impl @io.Writer for ServerConnection with write_reader(self, reader) {
  if self.h2 is Some(_) {
    let buf : FixedArray[Byte] = FixedArray::make(16384, b'\x00')
    for {
      let n = reader._direct_read(buf, offset=0, max_len=buf.length())
      if n == 0 {
        break
      }
      self.write(buf.unsafe_reinterpret_as_bytes()[:n])
    }
  } else {
    guard not(self.sender.mode is SendingHeader)
    self.sender.write_reader(reader)
  }
}

///|
/// Flush buffered data in the response body being sent, if any.
pub async fn ServerConnection::flush(self : ServerConnection) -> Unit {
  if self.h2 is Some(_) {
    () // H2 sends DATA frames immediately
  } else {
    self.sender.flush()
  }
}

///|
/// End the body of the response currently being sent.
/// Should be called immediately after response body is fully sent.
pub async fn ServerConnection::end_response(self : ServerConnection) -> Unit {
  if self.h2 is Some(h2) {
    // Send empty DATA frame with END_STREAM
    h2.stream.send_data(Bytes::make(0, b'\x00'), end_stream=true)
  } else {
    self.sender.end_body()
  }
}

///|
/// Send a response to the peer.
/// The `ServerConnection` can be used as a `@io.Writer` later for sending response body.
/// After calling `send_response`,
/// `end_response` must be called before sending the next response.
pub async fn ServerConnection::send_response(
  self : ServerConnection,
  code : Int,
  reason : String,
  extra_headers? : Map[String, String] = {},
) -> Unit {
  if self.h2 is Some(h2) {
    ignore(reason)
    h2.server_conn.send_response(h2.stream, code, headers=extra_headers)
    h2.response_sent = true
  } else {
    self.sender.send_response(code, reason, extra_headers~)
  }
}

///|
/// Create a HTTP server listening on `addr` and run its main loop.
/// New connections are handled by the callback `f`,
/// `f` will receive the new HTTP connection and the address of the client.
///
/// The client connection is closed automatically,
/// so `f` must not close the connection manually.
///
/// `headers` can be used to specify persistent headers for the server,
/// i.e. all response sent by this server will share these headers.
///
/// If `allow_failure` is `true` (`true` by default),
/// failure in `f` will be silently ignored.
///
/// If `max_connections` is present,
/// at most `max_connections` clients are allowed in parallel.
/// New clients will only get handled after a previous client terminates.
///
/// The meaning of `dual_stack` and `reuse_addr` is the same as `@socket.TcpServer::new`,
/// see its document for more details.
#deprecated("use `@http.Server::run_forever()` instead")
pub async fn run_server(
  addr : @socket.Addr,
  f : async (ServerConnection, @socket.Addr) -> Unit,
  headers? : Map[String, String],
  dual_stack? : Bool,
  reuse_addr? : Bool,
  allow_failure? : Bool,
  max_connections? : Int,
) -> Unit {
  @socket.TcpServer::new(addr, dual_stack?, reuse_addr?).run_forever(
    allow_failure?,
    max_connections?,
    (conn, addr) => {
      let conn = ServerConnection::new(conn, headers?)
      f(conn, addr)
    },
  )
}

///|
/// TLS configuration for a HTTP server
priv struct TlsConfig {
  certificate_file : String
  certificate_type : @tls.X509FileType
  private_key_file : String
  private_key_type : @tls.X509FileType
}

///|
/// A HTTP server
struct Server {
  server : @socket.TcpServer
  headers : Map[String, String]
  tls : TlsConfig?
}

///|
/// Create a new HTTP server listening on `addr`.
///
/// The meaning of `dual_stack` and `reuse_addr` is the same as
/// `@socket.TcpServer::new()`, see there for more details.
///
/// `headers` can be used to specify common headers
/// shared by all responses sent by this server.
pub fn Server::new(
  addr : @socket.Addr,
  dual_stack? : Bool,
  reuse_addr? : Bool,
  headers? : Map[String, String] = {},
  tls_certificate_file? : String,
  tls_certificate_type? : @tls.X509FileType = PEM,
  tls_private_key_file? : String,
  tls_private_key_type? : @tls.X509FileType = PEM,
) -> Server raise {
  let tls : TlsConfig? = match tls_certificate_file {
    Some(cert) =>
      match tls_private_key_file {
        Some(key) =>
          Some({
            certificate_file: cert,
            certificate_type: tls_certificate_type,
            private_key_file: key,
            private_key_type: tls_private_key_type,
          })
        None => None
      }
    None => None
  }
  {
    server: @socket.TcpServer::new(addr, dual_stack?, reuse_addr?),
    headers,
    tls,
  }
}

///|
pub fn Server::close(self : Server) -> Unit {
  self.server.close()
}

///|
/// Get the listen address of the server
pub fn Server::addr(self : Server) -> @socket.Addr {
  self.server.addr()
}

///|
/// Accept a new connection from a HTTP server.
/// Return the new HTTP connection and the address of peer.
pub async fn Server::accept(self : Server) -> (ServerConnection, @socket.Addr) {
  let (conn, addr) = self.server.accept()
  // TLS + H2 negotiation is handled in run_forever; accept returns H1 only
  (ServerConnection::new(conn, headers=self.headers), addr)
}

///|
/// Start the main loop of a HTTP server,
/// the server will keep listening for new connections
/// and new requests from existing connections.
/// Requests are handled by the callback function `f`.
///
/// The callback function `f` accepts three arguments:
/// - the request to process
/// - a `&@io.Reader` that can be used to read request body
/// - a `@http.ServerConnection` that can be used to send response.
///     The procedure to send a response is:
///     1. initiate a response and send response header via `.send_response()`
///     2. send response body by using the `@http.ServerConnection` as `@io.Writer`
///     3. (optional) complete the response via `.end_response()`.
///         If `.end_response()` is not called, it will be called automatically
///         after `f` returns.
///
/// If `allow_failure` is `true` (`true` by default),
/// error raised by `f` will not crash the whole server.
/// In this case, `run_forever` will only terminate when cancelled externally.
/// Note that if `f` fails, the connection used by `f` will still get aborted.
///
/// If `max_connections` is present,
/// at most `max_connections` clients are allowed in parallel.
/// New clients will only get handled after a previous client terminates.
///
/// If `f` fails without closing the connection, 
/// `run_forever` will close each connection automatically.
/// If `f` manually closes the connection,
/// the connection will be dropped after `f` returns.
/// On error or cancellation, the server will be closed automatically.
pub async fn Server::run_forever(
  self : Server,
  f : async (Request, &@io.Reader, ServerConnection) -> Unit,
  allow_failure? : Bool,
  max_connections? : Int,
) -> Unit {
  self.server.run_forever(allow_failure?, max_connections?, (tcp_conn, _) => {
    match self.tls {
      Some(tls_config) => {
        let tls = @tls.Tls::server(
          tcp_conn,
          private_key_file=tls_config.private_key_file,
          private_key_type=tls_config.private_key_type,
          certificate_file=tls_config.certificate_file,
          certificate_type=tls_config.certificate_type,
          alpn=["h2", "http/1.1"],
        )
        defer tls.close()
        if tls.selected_alpn() is Some("h2") {
          // HTTP/2 mode
          let h2_conn = @http2.H2ServerConnection::new(tls, tls)
          @async.with_task_group(async fn(group) {
            group.spawn_bg(no_wait=true, allow_failure=true, async fn() {
              h2_conn.run_read_loop()
            })
            group.add_defer(async fn() { h2_conn.close() })
            for {
              let stream = h2_conn.accept_stream() catch { _ => break }
              let headers = stream.wait_headers() catch { _ => continue }
              let request = build_h2_request(headers)
              let sc : ServerConnection = {
                reader: Reader::new(tls),
                conn: tcp_conn,
                sender: Sender::new(tls, headers=self.headers),
                closed: false,
                h2: Some({ server_conn: h2_conn, stream, response_sent: false }),
              }
              group.spawn_bg(allow_failure?, async fn() {
                f(request, sc, sc)
                if not(sc.closed) {
                  if sc.h2 is Some(h2) && h2.response_sent {
                    sc.end_response()
                  }
                }
              })
            }
          })
        } else {
          // HTTP/1.1 over TLS
          let conn : ServerConnection = {
            reader: Reader::new(tls),
            conn: tcp_conn,
            sender: Sender::new(tls, headers=self.headers),
            closed: false,
            h2: None,
          }
          defer conn.close()
          for {
            let request = conn.read_request()
            f(request, conn, conn)
            if conn.closed {
              break
            } else if conn.sender.mode is (WaitingBody | SendingBody) {
              conn.end_response()
            }
          }
        }
      }
      None => {
        // Plain HTTP/1.1 (no TLS)
        let conn = ServerConnection::new(tcp_conn, headers=self.headers)
        defer conn.close()
        for {
          let request = conn.read_request()
          f(request, conn, conn)
          if conn.closed {
            break
          } else if conn.sender.mode is (WaitingBody | SendingBody) {
            conn.end_response()
          }
        }
      }
    }
  })
}

///|
/// Let the server enter "pass through" mode,
/// where the server serve as a TCP tunnel (maybe TLS encrypted) directly.
/// This is useful for handling the special `CONNECT` HTTP request and HTTP protcol upgrade.
///
/// In passthrough mode,
/// Read/write the server becomes direct read/write on the underlying connection,
/// and all API except `@io.Reader` and `@io.Writer` must not be used anymore.
///
/// When entering pass through mode,
/// the server must be in a clean state
/// (i.e. not in the middle of sending a response).
/// Unread data from the body of the last request will be discarded.
pub async fn ServerConnection::enter_passthrough_mode(self : Self) -> Unit {
  guard self.h2 is None else {
    abort("enter_passthrough_mode is not supported for HTTP/2")
  }
  guard self.sender.mode is SendingHeader
  self.reader.enter_passthrough_mode()
  self.sender.enter_passthrough_mode()
}

///|
fn build_h2_request(headers : Map[String, String]) -> Request {
  let meth = match headers.get(":method") {
    Some("GET") => Get
    Some("HEAD") => Head
    Some("POST") => Post
    Some("PUT") => Put
    Some("DELETE") => Delete
    Some("CONNECT") => Connect
    Some("OPTIONS") => Options
    Some("TRACE") => Trace
    Some("PATCH") => Patch
    _ => Get
  }
  let path = match headers.get(":path") {
    Some(p) => p
    None => "/"
  }
  let request_headers : Map[String, String] = {}
  for k, v in headers {
    if k.length() > 0 && k[0] != ':' {
      request_headers[k] = v
    }
  }
  { meth, path, headers: request_headers }
}
