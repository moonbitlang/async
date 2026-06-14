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
#external
priv type JsHeaders

///|
fn JsHeaders::new() -> JsHeaders = "moonbitlang_async_http" "new_headers"

///|
fn JsHeaders::append(headers : JsHeaders, name : String, value : String) = "moonbitlang_async_http" "headers_append"

///|
fn JsHeaders::for_each(
  headers : JsHeaders,
  callback : (String, String) -> Unit,
) -> Unit = "moonbitlang_async_http" "headers_for_each"

///|
#external
priv type JsResponse

///|
fn JsResponse::status(response : JsResponse) -> Int = "moonbitlang_async_http" "response_status"

///|
fn JsResponse::status_text(response : JsResponse) -> String = "moonbitlang_async_http" "response_status_text"

///|
fn JsResponse::headers(response : JsResponse) -> JsHeaders = "moonbitlang_async_http" "response_headers"

///|
/// Local externref aliases for cross-package types used in WASM import
/// signatures. The wasm-gc backend requires WASM import parameters and
/// return types to be defined in the same compilation unit.
#external
priv type RawExternRef

///|
fn[X, Y] raw_cast(x : X) -> Y = "%identity"

///|
fn wasm_response_body(response : JsResponse) -> RawExternRef = "moonbitlang_async_http" "response_body"

///|
fn JsResponse::body(response : JsResponse) -> @js_async.JsReadableStream {
  raw_cast(wasm_response_body(response))
}

///|
priv struct OngoingRequest {
  body_writer : @io.PipeWrite
  abort_controller : @js_async.AbortController
  response : @js_async.Promise[JsResponse]
}

///|
struct Client {
  host : String
  port : Int
  protocol : Protocol
  headers : Map[String, String]
  mut request : OngoingRequest?
  mut response_body : @js_async.ReadableStream?
}

///|
pub fn Client::close(self : Client) -> Unit {
  if self.request is Some(request) {
    request.body_writer.close()
    self.request = None
  }
  if self.response_body is Some(response_body) {
    response_body.close()
  }
}

///|
fn Client::connect(
  host : String,
  headers? : Map[String, String] = {},
  protocol? : Protocol = Https,
  port? : Int = protocol.default_port(),
  proxy? : Client,
) -> Client {
  ignore(proxy)
  { host, headers, protocol, port, request: None, response_body: None }
}

///|
/// Create a new HTTP client by connecting to a remote host.
/// Host should be specified via `protocol://host[:port]`,
/// where `protocol` is one of `http` or `https`.
///
/// `headers` can be used to specify persistent headers for the client,
/// i.e. all requests made from this client will share these headers.
/// The ownership of `headers` will be transferred to the new client,
/// so `headers` should not be used by the caller later.
/// The headers mentioned in
/// https://developer.mozilla.org/en-US/docs/Glossary/Forbidden_request_header
/// must not be set in `headers`.
///
/// The HTTP client make requests using native fetch API.
///
/// The `proxy` argument is not supported on wasm-gc backend and has no effect.
#warnings("-unused_async")
pub async fn Client::new(
  uri : String,
  headers? : Map[String, String] = {},
  proxy? : Client,
) -> Client {
  ignore(proxy)
  let (protocol, port, host, path) = resolve_url(uri)
  guard path is "/" else { raise InvalidFormat }
  Client::connect(host, protocol~, port~, headers~, proxy?)
}

///|
pub impl @io.Writer for Client with write_once(self, buf, offset~, len~) {
  guard self.request is Some(request)
  request.body_writer.write_once(buf, offset~, len~)
}

///|
#warnings("-unused_async")
pub async fn Client::flush(_ : Client) -> Unit {
  ()
}

///|
pub impl @io.Reader for Client with _get_internal_buffer(self) {
  guard self.response_body is Some(stream)
  stream._get_internal_buffer()
}

///|
pub impl @io.Reader for Client with _direct_read(self, buf, offset~, max_len~) {
  guard self.response_body is Some(stream)
  stream._direct_read(buf, offset~, max_len~)
}

///|
pub async fn Client::end_request(self : Client) -> Response {
  guard self.request is Some(request)
  self.request = None
  request.body_writer.close()
  let js_response : JsResponse = request.response.wait(
    abort_controller=request.abort_controller,
  )
  self.response_body = Some(
    @js_async.ReadableStream::from_js(js_response.body()),
  )
  let headers = {}
  js_response
  .headers()
  .for_each(fn(name, value) { headers[name.to_lower()] = value })
  { code: js_response.status(), reason: js_response.status_text(), headers }
}

///|
fn wasm_fetch_request(
  uri : String,
  meth : String,
  headers : JsHeaders,
  body : RawExternRef,
  signal : RawExternRef,
) -> RawExternRef = "moonbitlang_async_http" "fetch_request"

///|
fn request_ffi(
  uri : String,
  meth : String,
  headers : JsHeaders,
  body : @js_async.JsReadableStream,
  signal : @js_async.AbortSignal,
) -> @js_async.Promise[JsResponse] {
  raw_cast(
    wasm_fetch_request(uri, meth, headers, raw_cast(body), raw_cast(signal)),
  )
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
/// In addition to headers in `Client::new`,
/// extra HTTP headers can be passed via `extra_headers`.
/// The headers mentioned in
/// https://developer.mozilla.org/en-US/docs/Glossary/Forbidden_request_header
/// must not be set in `extra_headers`.
#warnings("-unused_async")
pub async fn Client::request(
  self : Client,
  meth : RequestMethod,
  path : String,
  extra_headers? : Map[String, String] = {},
) -> Unit {
  guard self.request is None
  let protocol = match self.protocol {
    Http => "http://"
    Https => "https://"
  }
  let path = if path is ['/', ..] { path } else { "/\{path}" }
  let port = if self.port == self.protocol.default_port() {
    ""
  } else {
    ":\{self.port}"
  }
  let uri = "\{protocol}\{self.host}\{port}\{path}"
  let meth = match meth {
    Get => "GET"
    Head => "HEAD"
    Post => "POST"
    Put => "PUT"
    Delete => "DELETE"
    Connect => "CONNECT"
    Options => "OPTIONS"
    Trace => "TRACE"
    Patch => "PATCH"
  }
  let headers = JsHeaders::new()
  for k, v in self.headers {
    headers.append(k, v)
  }
  for k, v in extra_headers {
    headers.append(k, v)
  }
  let abort_controller = @js_async.AbortController::new()
  let (body, we_write) = @js_async.JsReadableStream::new_pipe()
  let response_promise = request_ffi(
    uri,
    meth,
    headers,
    body,
    abort_controller.signal(),
  )
  let request : OngoingRequest = {
    abort_controller,
    body_writer: we_write,
    response: response_promise,
  }
  self.request = Some(request)
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
