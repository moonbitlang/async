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
/// Simple HTTP client which connect to a remote host via TCP
struct Client {
  headers : Array[Header]
  reader : Reader
  conn : @socket.TCP
  tls : @tls.TLS?
}

///|
/// Create a new HTTP client by connecting to a remote host.
/// If `protocol` is `Https` (`Https` by default),
/// a TLS connection will be established,
/// and the certificate of the remote peer will be verified.
///
/// `headers` can be used to specify persistent headers for the client,
/// i.e. all requests made from this client will share these headers.
/// The ownership of `headers` will be transferred to the new client,
/// so `headers` should not be used by the caller later.
/// The following headers is automatically set,
/// and must not be specified in `headers`:
/// 
/// - Host
/// - Content-Length, Transfer-Encoding
pub async fn Client::connect(
  host : Bytes,
  headers? : Array[Header] = [],
  protocol? : Protocol = Https,
  port? : Int = protocol.default_port(),
) -> Client raise {
  let conn = @socket.TCP::connect_to_host(host, port~)
  let tls = match protocol {
    Http => None
    Https => Some(@tls.TLS::client(conn, host~))
  }
  let reader = match tls {
    None => Reader::new(conn)
    Some(tls) => Reader::new(tls)
  }
  headers.push(Header("Host", host))
  { headers, conn, tls, reader }
}

///|
/// Close a HTTP client and release underlying resource.
/// In particular close the underlying TCP connection.
pub fn Client::close(self : Client) -> Unit {
  if self.tls is Some(tls) {
    tls.close()
  }
  self.conn.close()
}

///|
/// Gracefully shutdown a HTTP client, in particular perform TLS shutdown.
/// This MUST be called before `close`
/// and MUST NOT be called on fatal network or TLS error.
#deprecated("TLS shutdown is not necessary for HTTP/1.1, and bad server may cause this to hang")
pub async fn Client::shutdown(self : Client) -> Unit raise {
  if self.tls is Some(tls) {
    tls.shutdown()
  }
}

///|
pub impl @io.Reader for Client with read(
  self,
  buf,
  offset? = 0,
  max_len? = buf.length() - offset,
) {
  self.reader.read(buf, offset~, max_len~)
}

///|
/// Send a HTTP request to the server, and return the response from the server.
/// Only the header of the response will be received and returned,
/// the body of the response can be extracted by using `Client` as a `@io.Reader`.
///
/// After performing a request,
/// the next request MUST NOT be made before the body of the response is consumed.
/// If you don't care about the response body, use `skip_body` to skip it.
///
/// In addition to headers in `Client::connect`,
/// extra HTTP headers can be passed via `extra_headers`.
/// The following headers is automatically set by `request`,
/// and must not be specified in `extra_headers`:
/// 
/// - Host
/// - Content-Length, Transfer-Encoding
pub async fn Client::request(
  self : Client,
  meth : RequestMethod,
  path : Bytes,
  extra_headers? : Array[Header] = [],
  body : Body,
) -> Response raise {
  let headers = self.headers + extra_headers
  match self.tls {
    Some(tls) => send_request(tls, { meth, path, headers }, body)
    None => send_request(self.conn, { meth, path, headers }, body)
  }
  self.reader.read_response()
}

///|
/// Skip the body of the response currently being produced,
/// so that the next request can be made.
pub async fn Client::skip_body(self : Client) -> Unit raise {
  self.reader.skip_body()
}

///|
/// Perform a `GET` request to the server, see `Client::request` for more details.
pub async fn Client::get(
  self : Client,
  path : Bytes,
  extra_headers? : Array[Header] = [],
  body? : Body = Empty,
) -> Response raise {
  self.request(Get, path, extra_headers~, body)
}

///|
/// Perform a `PUT` request to the server, see `Client::request` for more details.
pub async fn Client::put(
  self : Client,
  path : Bytes,
  body : Body,
  extra_headers? : Array[Header] = [],
) -> Response raise {
  self.request(Put, path, extra_headers~, body)
}

///|
/// Perform a `POST` request to the server, see `Client::request` for more details.
pub async fn Client::post(
  self : Client,
  path : Bytes,
  body : Body,
  extra_headers? : Array[Header] = [],
) -> Response raise {
  self.request(Post, path, extra_headers~, body)
}
