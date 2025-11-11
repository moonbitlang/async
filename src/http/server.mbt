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
/// A single HTTP server connection
struct ServerConnection {
  reader : Reader
  conn : @socket.Tcp
  sender : Sender
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
  { reader: Reader::new(conn), conn, sender: Sender::new(conn, headers~) }
}

///|
/// Close the connection, the underlying TCP connection will be closed as well.
pub fn ServerConnection::close(self : ServerConnection) -> Unit {
  self.conn.close()
}

///|
pub impl @io.Reader for ServerConnection with _direct_read(
  self,
  buf,
  offset~,
  max_len~,
) {
  self.reader._direct_read(buf, offset~, max_len~)
}

///|
pub impl @io.Reader for ServerConnection with _get_internal_buffer(self) {
  self.reader.read_buf
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
  self.reader.skip_body()
  self.reader.read_request()
}

///|
/// Manually discard the body of the request currently being processed.
pub async fn ServerConnection::skip_request_body(
  self : ServerConnection,
) -> Unit {
  self.reader.skip_body()
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
  guard self.sender.mode is SendingBody
  self.sender.write_once(buf, offset~, len~)
}

///|
pub impl @io.Writer for ServerConnection with write_reader(self, reader) {
  guard self.sender.mode is SendingBody
  self.sender.write_reader(reader)
}

///|
/// Flush buffered data in the response body being sent, if any.
pub async fn ServerConnection::flush(self : ServerConnection) -> Unit {
  self.sender.flush()
}

///|
/// End the body of the response currently being sent.
/// Should be called immediately after response body is fully sent.
pub async fn ServerConnection::end_response(self : ServerConnection) -> Unit {
  self.sender.end_body()
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
  self.sender.send_response(code, reason, extra_headers~)
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
/// The meaning of `dual_stack` is the same as `@socket.TcpServer::new`,
/// see its document for more details.
pub async fn run_server(
  addr : @socket.Addr,
  f : async (ServerConnection, @socket.Addr) -> Unit,
  headers? : Map[String, String],
  dual_stack? : Bool,
  allow_failure? : Bool,
  max_connections? : Int,
) -> Unit {
  @socket.TcpServer::new(addr, dual_stack?).run_forever(
    allow_failure?,
    max_connections?,
    fn(conn, addr) {
      let conn = ServerConnection::new(conn, headers?)
      f(conn, addr)
    },
  )
}
