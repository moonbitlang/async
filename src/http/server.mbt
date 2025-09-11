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
  send_buf : FixedArray[Byte]
  mut send_len : Int
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
  let reader = Reader::new(conn)
  let send_buf = FixedArray::make(1024, b'0')
  { headers, reader, conn, send_buf, send_len: 0 }
}

///|
/// Close the connection, the underlying TCP connection will be closed as well.
pub fn ServerConnection::close(self : ServerConnection) -> Unit {
  self.conn.close()
}

///|
pub impl @io.Reader for ServerConnection with read(self, buf, offset~, max_len~) {
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
pub async fn ServerConnection::read_request(
  self : ServerConnection,
) -> Request raise {
  self.reader.skip_body()
  self.reader.read_request()
}

///|
/// Manually discard the body of the request currently being processed.
pub async fn ServerConnection::skip_body(self : ServerConnection) -> Unit raise {
  self.reader.skip_body()
}

///|
async fn ServerConnection::flush(self : Self) -> Unit raise {
  if self.send_len > 0 {
    self.conn.write(self.send_buf.unsafe_reinterpret_as_bytes()[:self.send_len])
    self.send_len = 0
  }
}

///|
impl @io.Writer for ServerConnection with write_once(self, buf, offset~, len~) {
  if self.send_len >= self.send_buf.length() {
    self.flush()
  }
  let len = @cmp.minimum(len, self.send_buf.length() - self.send_len)
  self.send_buf.blit_from_bytes(self.send_len, buf, offset, len)
  self.send_len += len
  len
}

///|
/// Send a response to the peer.
pub async fn ServerConnection::send_response(
  self : ServerConnection,
  code : Int,
  reason : Bytes,
  body : Body,
  extra_headers? : Array[Header] = [],
) -> Unit raise {
  self
  ..write("HTTP/1.1 ")
  ..write(encode_int(code, base=10))
  ..write(" ")
  ..write(reason)
  ..write("\r\n")
  send_headers(self, self.headers)
  send_headers(self, extra_headers)
  send_body_headers(self, body)
  self.write("\r\n")
  self.flush()
  match body {
    Empty => ()
    Fixed(body) => self.conn.write(body)
    Stream(body) => send_body_chunked(self.conn, self.send_buf, body)
  }
}
