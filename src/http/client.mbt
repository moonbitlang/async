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
  sender : Sender
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
  host : String,
  headers? : Array[Header] = [],
  protocol? : Protocol = Https,
  port? : Int = protocol.default_port(),
) -> Client {
  let conn = @socket.TCP::connect_to_host(host, port~)
  let tls = match protocol {
    Http => None
    Https => Some(@tls.TLS::client(conn, host~))
  }
  let reader = match tls {
    None => Reader::new(conn)
    Some(tls) => Reader::new(tls)
  }
  let sender = match tls {
    None => Sender::new(conn)
    Some(tls) => Sender::new(tls)
  }
  headers.push(Header("Host", host))
  { headers, conn, tls, reader, sender }
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
pub async fn Client::shutdown(self : Client) -> Unit {
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
/// Write data to the body of the request currently being sent.
/// Must be called after `send_request`.
/// `end_request` must be called after all content of response body has been sent.
pub impl @io.Writer for Client with write_once(self, buf, offset~, len~) {
  guard self.sender.mode is SendingBody
  self.sender.write_once(buf, offset~, len~)
}

///|
/// End the body of the request currently being sent,
/// and obtain response from the server.
/// Should be called immediately after request body is fully sent.
///
/// Only the header of the response will be received and returned,
/// the body of the response can be extracted by using `Client` as a `@io.Reader`.
///
/// If the body of the last response is still not consumed,
/// it will be discarded.
pub async fn Client::end_request(self : Client) -> Response {
  self.sender.end_body()
  self.reader.skip_body()
  self.reader.read_response()
}

///|
/// Send a HTTP request to the server.
/// Only the header of the request will be sent,
/// request body can be sent by using `Client` as a `@io.Writer`.
/// Once request body has been sent,
/// `end_request` must be called to complete the request and obtain response from the server.
///
/// After performing a request,
/// the next request MUST NOT be made before the request is completed via `end_request`.
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
  path : String,
  extra_headers? : Array[Header] = [],
) -> Unit {
  match meth {
    Get => self.sender.write("GET ")
    Head => self.sender.write("HEAD ")
    Post => self.sender.write("POST ")
    Put => self.sender.write("PUT ")
    Delete => self.sender.write("DELETE ")
    Connect => self.sender.write("CONNECT ")
    Options => self.sender.write("OPTIONS ")
    Trace => self.sender.write("TRACE ")
    Patch => self.sender.write("PATCH ")
  }
  self.sender..write_string(path, encoding=UTF8)..write(" HTTP/1.1\r\n")
  self.sender.send_headers(self.headers)
  self.sender.send_headers(extra_headers)
  self.sender.write("Transfer-Encoding: chunked\r\n")
  self.sender.start_body()
}

///|
/// Skip the body of the response currently being produced,
/// so that the next request can be made.
pub async fn Client::skip_response_body(self : Client) -> Unit {
  self.reader.skip_body()
}

///|
/// Perform a `GET` request to the server, see `Client::request` for more details.
pub async fn Client::get(
  self : Client,
  path : String,
  extra_headers? : Array[Header] = [],
) -> Response {
  self.request(Get, path, extra_headers~)
  self.end_request()
}

///|
/// Perform a `PUT` request to the server, see `Client::request` for more details.
pub async fn[B : Body] Client::put(
  self : Client,
  path : String,
  body : B,
  extra_headers? : Array[Header] = [],
) -> Response {
  self.request(Put, path, extra_headers~)
  body.write(self.sender)
  self.end_request()
}

///|
/// Perform a `POST` request to the server, see `Client::request` for more details.
pub async fn[B : Body] Client::post(
  self : Client,
  path : String,
  body : B,
  extra_headers? : Array[Header] = [],
) -> Response {
  self.request(Post, path, extra_headers~)
  body.write(self.sender)
  self.end_request()
}
