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
  reader : Reader
  conn : @socket.Tcp
  tls : @tls.Tls?
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
///
/// If `proxy` is provided, the connection will be established through
/// the specified HTTP proxy using the CONNECT method.
pub async fn Client::connect(
  host : String,
  headers? : Map[String, String] = {},
  protocol? : Protocol = Https,
  port? : Int = protocol.default_port(),
  proxy? : Proxy,
) -> Client {
  let conn = match proxy {
    None => @socket.Tcp::connect_to_host(host, port~)
    Some(proxy) =>
      match proxy.should_use(protocol) {
        Some((proxy_host, proxy_port)) =>
          connect_through_proxy(proxy_host, proxy_port, host, port)
        None => @socket.Tcp::connect_to_host(host, port~)
      }
  }
  let tls = match protocol {
    Http => None
    Https => Some(@tls.Tls::client(conn, host~))
  }
  let reader = match tls {
    None => Reader::new(conn)
    Some(tls) => Reader::new(tls)
  }
  headers["Host"] = host
  let sender = match tls {
    None => Sender::new(conn, headers~)
    Some(tls) => Sender::new(tls, headers~)
  }
  { conn, tls, reader, sender }
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
pub impl @io.Reader for Client with _direct_read(self, buf, offset~, max_len~) {
  self.reader._direct_read(buf, offset~, max_len~)
}

///|
pub impl @io.Reader for Client with _get_internal_buffer(self) {
  self.reader.read_buf
}

///|
/// Write data to the body of the request currently being sent.
/// Must be called after `send_request`.
/// `end_request` must be called after all content of response body has been sent.
///
/// Writing to `@http.Client` MAY be buffered,
/// call `flush` manually to ensure data is delivered to the remote peer.
pub impl @io.Writer for Client with write_once(self, buf, offset~, len~) {
  guard self.sender.mode is SendingBody
  self.sender.write_once(buf, offset~, len~)
}

///|
pub impl @io.Writer for Client with write_reader(self, reader) {
  guard self.sender.mode is SendingBody
  self.sender.write_reader(reader)
}

///|
/// Flush buffered data in the request body being sent, if any.
pub async fn Client::flush(self : Client) -> Unit {
  self.sender.flush()
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
  extra_headers? : Map[String, String] = {},
) -> Unit {
  self.sender.send_request(meth, path, extra_headers~)
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
  extra_headers? : Map[String, String] = {},
  body? : &@io.Data,
) -> Response {
  self.request(Get, path, extra_headers~)
  if body is Some(body) {
    self.write(body)
  }
  self.end_request()
}

///|
/// Perform a `PUT` request to the server, see `Client::request` for more details.
pub async fn Client::put(
  self : Client,
  path : String,
  body : &@io.Data,
  extra_headers? : Map[String, String] = {},
) -> Response {
  self..request(Put, path, extra_headers~)..write(body).end_request()
}

///|
/// Perform a `POST` request to the server, see `Client::request` for more details.
pub async fn Client::post(
  self : Client,
  path : String,
  body : &@io.Data,
  extra_headers? : Map[String, String] = {},
) -> Response {
  self..request(Post, path, extra_headers~)..write(body).end_request()
}
