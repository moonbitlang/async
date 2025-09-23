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
  headers : Array[Header]
  reader : Reader
  conn : @socket.TCP
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
  conn : @socket.TCP,
  headers? : Array[Header] = [],
) -> ServerConnection {
  { headers, reader: Reader::new(conn), conn, sender: Sender::new(conn) }
}

///|
/// Close the connection, the underlying TCP connection will be closed as well.
pub fn ServerConnection::close(self : ServerConnection) -> Unit {
  self.conn.close()
}

///|
pub impl @io.Reader for ServerConnection with read(
  self,
  buf,
  offset? = 0,
  max_len? = buf.length() - offset,
) {
  self.reader.read(buf, offset~, max_len~)
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
  reason : Bytes,
  extra_headers? : Array[Header] = [],
) -> Unit {
  guard self.sender.mode is SendingHeader
  self.sender
  ..write("HTTP/1.1 ")
  ..write(encode_int(code, base=10))
  ..write(" ")
  ..write(reason)
  ..write("\r\n")
  self.sender.send_headers(self.headers)
  self.sender.send_headers(extra_headers)
  self.sender.write("Transfer-Encoding: chunked\r\n")
  self.sender.start_body()
}
