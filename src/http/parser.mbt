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
priv enum BodyKind {
  Empty
  Fixed(Int)
  Chunked(Int)
  PassThrough
}

///|
/// A HTTP reader type that can parse and deliver HTTP request/response
priv struct Reader {
  mut body : BodyKind
  transport : &@io.Reader
  read_buf : @io.ReaderBuffer
}

///|
/// Create a new HTTP reader wrapping around existing reader `transport`.
/// The HTTP reader will read data from `transport`.
fn[R : @io.Reader] Reader::new(transport : R) -> Reader {
  { body: Empty, transport, read_buf: @io.ReaderBuffer::new() }
}

///|
pub suberror HttpProtocolError {
  BadRequest
  HttpVersionNotSupported(String)
  NotImplemented
} derive(Show, ToJson)

///|
/// Read from the body of the HTTP request/response
/// that is currently being processed by the HTTP reader.
/// All reader related API of `HttpReader` should be called
/// after a successful call to `read_request` or `read_response`,
/// otherwise reading always result in EOF.
impl @io.Reader for Reader with _direct_read(self, buf, offset~, max_len~) {
  match self.body {
    Empty => 0
    Fixed(remaining) => {
      let max_len = @cmp.minimum(max_len, remaining)
      let n = self.transport.read(buf, offset~, max_len~)
      let remaining = remaining - n
      self.body = if remaining == 0 { Empty } else { Fixed(remaining) }
      n
    }
    Chunked(0) => {
      guard self.transport.read_until("\r\n") is Some(len_str) else {
        raise @io.ReaderClosed
      }
      let next_chunk_len = @strconv.parse_int(len_str, base=16) catch {
        _ => raise BadRequest
      }
      guard next_chunk_len > 0 else {
        guard self.transport.read_exactly(2) == "\r\n" else { raise BadRequest }
        self.body = Empty
        return 0
      }
      let max_len = @cmp.minimum(next_chunk_len, max_len)
      let n = self.transport.read(buf, offset~, max_len~)
      let remaining = next_chunk_len - n
      if remaining == 0 {
        guard self.transport.read_exactly(2) == "\r\n" else { raise BadRequest }
      }
      self.body = Chunked(remaining)
      n
    }
    Chunked(first_chunk_remaining) => {
      let max_len = @cmp.minimum(first_chunk_remaining, max_len)
      let n = self.transport.read(buf, offset~, max_len~)
      let remaining = first_chunk_remaining - n
      if remaining == 0 {
        guard self.transport.read_exactly(2) == "\r\n" else { raise BadRequest }
      }
      self.body = Chunked(remaining)
      n
    }
    PassThrough => self.transport._direct_read(buf, offset~, max_len~)
  }
}

///|
impl @io.Reader for Reader with _get_internal_buffer(self) {
  if self.body is PassThrough {
    self.transport._get_internal_buffer()
  } else {
    self.read_buf
  }
}

///|
async fn Reader::read_headers(self : Reader) -> Map[String, String] {
  let headers = {}
  for {
    guard self.transport.read_until("\r\n") is Some(header_line) else {
      raise @io.ReaderClosed
    }
    if header_line is "" {
      // empty line indicates end of header
      break
    }
    guard header_line.find(":") is Some(colon_index) else { raise BadRequest }
    let key = header_line[:colon_index].to_lower().to_string()
    guard colon_index + 1 < header_line.length() else { raise BadRequest }
    let value_start = if header_line.code_unit_at(colon_index + 1) == ' ' {
      colon_index + 2
    } else {
      colon_index + 1
    }
    let value = header_line[value_start:].to_string()
    match headers.get(key) {
      None => headers[key] = value
      Some(value0) => headers[key] = "\{value0},\{value}"
    }
    match key {
      "content-length" => {
        guard not(self.body is Fixed(_)) else { raise BadRequest }
        let len = @strconv.parse_int(value, base=10)
        if self.body is Empty && len > 0 {
          self.body = Fixed(len)
        }
      }
      "transfer-encoding" => {
        guard not(self.body is Chunked(_)) else { raise BadRequest }
        guard value.to_lower() is "chunked" else { raise NotImplemented }
        self.body = Chunked(0)
      }
      _ => ()
    }
  }
  headers
}

///|
/// Read the header of a HTTP/1.1 request from a HTTP reader.
/// This function must be called after the body of the last request is consumed,
/// otherwise it will abort the program immediately.
/// If the body is not needed, use `HttpReader::skip_body` to discard it.
///
/// After `read_request` successfully returned,
/// the HTTP reader itself can be used to extract the body of the request.
///
/// HTTP header fields are case insensitive.
/// In the result of `read_request`, all header fields will be in lower case.
async fn Reader::read_request(self : Reader) -> Request {
  guard self.body is Empty
  guard self.transport.read_until("\r\n") is Some(request_line) else {
    raise @io.ReaderClosed
  }
  guard request_line.find(" ") is Some(meth_len) else { raise BadRequest }
  let meth = match request_line[:meth_len] {
    "GET" => Get
    "HEAD" => Head
    "POST" => Post
    "PUT" => Put
    "DELETE" => Delete
    "CONNECT" => Connect
    "OPTIONS" => Options
    "TRACE" => Trace
    "PATCH" => Patch
    _ => raise BadRequest
  }
  let request_line = request_line[meth_len + 1:]
  guard request_line.find(" ") is Some(path_len) else { raise BadRequest }
  let path = request_line[:path_len].to_string()
  match request_line[path_len + 1:] {
    "HTTP/1.1" | "HTTP/1.0" => ()
    protocol => raise HttpVersionNotSupported(protocol.to_string())
  }
  let headers = self.read_headers()
  { meth, path, headers }
}

///|
/// Read the header of a HTTP/1.1 response from a HTTP reader.
/// This function must be called after the body of the last response is consumed,
/// otherwise it will abort the program immediately.
/// If the body is not needed, use `HttpReader::skip_body` to discard it.
///
/// After `read_response` successfully returned,
/// the HTTP reader itself can be used to extract the body of the response.
///
/// HTTP header fields are case insensitive.
/// In the result of `read_response`, all header fields will be in lower case.
async fn Reader::read_response(self : Reader) -> Response {
  guard self.body is Empty
  guard self.transport.read_until("\r\n") is Some(response_line) else {
    raise @io.ReaderClosed
  }
  guard response_line.find(" ") is Some(protocol_len) else { raise BadRequest }
  match response_line[:protocol_len] {
    "HTTP/1.1" | "HTTP/1.0" => ()
    protocol => raise HttpVersionNotSupported(protocol.to_string())
  }
  let response_line = response_line[protocol_len + 1:]
  guard response_line.find(" ") is Some(code_len) else { raise BadRequest }
  let code = @strconv.parse_int(response_line[:code_len], base=10) catch {
    _ => raise BadRequest
  }
  let reason = response_line[code_len + 1:].to_string()
  let headers = self.read_headers()
  { code, reason, headers }
}

///|
/// Discard the body of current HTTP request/response,
/// so that the next request/response can be processed.
async fn Reader::skip_body(self : Reader) -> Unit {
  if self.body is Empty {
    return
  }
  while self.drop(1024) == 1024 {

  }
}

///|
fn @io.ReaderBuffer::get_repr(self : Self) -> @io_buffer.Buffer = "%identity"

///|
async fn Reader::enter_passthrough_mode(self : Reader) -> Unit {
  self.skip_body()
  self.read_buf.get_repr().clear()
  self.body = PassThrough
}
