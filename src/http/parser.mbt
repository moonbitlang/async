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
}

///|
/// A HTTP reader type that can parse and deliver HTTP request/response
struct Reader {
  mut body : BodyKind
  transport : @io.BufferedReader[&@io.Reader]
}

///|
/// Create a new HTTP reader wrapping around existing reader `transport`.
/// The HTTP reader will read data from `transport`.
pub fn[R : @io.Reader] Reader::new(transport : R) -> Reader {
  { body: Empty, transport: @io.BufferedReader::new(transport as &@io.Reader) }
}

///|
pub suberror HttpProtocolError {
  BadRequest
  HttpVersionNotSupported(String)
  NotImplemented
} derive(Show)

///|
/// Read from the body of the HTTP request/response
/// that is currently being processed by the HTTP reader.
/// All reader related API of `HttpReader` should be called
/// after a successful call to `read_request` or `read_response`,
/// otherwise reading always result in EOF.
pub impl @io.Reader for Reader with read(
  self,
  buf,
  offset? = 0,
  max_len? = buf.length() - offset,
) {
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
      let len_end = self.transport.find("\r\n")
      guard parse_int(self.transport[:len_end], base=16) is Some(next_chunk_len) else {
        raise BadRequest
      }
      self.transport.drop(len_end + 2)
      guard next_chunk_len > 0 else {
        guard self.transport[:2] == "\r\n" else { raise BadRequest }
        self.transport.drop(2)
        self.body = Empty
        return 0
      }
      let max_len = @cmp.minimum(next_chunk_len, max_len)
      let n = self.transport.read(buf, offset~, max_len~)
      let remaining = next_chunk_len - n
      if remaining == 0 {
        self.transport.drop(2) // \r\n
      }
      self.body = Chunked(remaining)
      n
    }
    Chunked(first_chunk_remaining) => {
      let max_len = @cmp.minimum(first_chunk_remaining, max_len)
      let n = self.transport.read(buf, offset~, max_len~)
      let remaining = first_chunk_remaining - n
      if remaining == 0 {
        self.transport.drop(2) // \r\n
      }
      self.body = Chunked(remaining)
      n
    }
  }
}

///|
async fn Reader::read_headers(self : Reader) -> Array[Header] raise {
  let headers = []
  for {
    let line_end = self.transport.find(b"\r\n")
    if line_end == 0 {
      // empty line indicates end of header
      self.transport.drop(line_end + 2)
      break
    }
    let header_line = self.transport[:line_end]
    guard header_line[:].find_index(':') is Some(colon_index) else {
      raise BadRequest
    }
    let key = header_line[:colon_index].to_lower_case()
    guard colon_index + 1 < header_line.length() else { raise BadRequest }
    let value_start = if header_line[colon_index + 1] == ' ' {
      colon_index + 2
    } else {
      colon_index + 1
    }
    let value = header_line[value_start:].to_bytes()
    headers.push(Header(key, value))
    match key {
      "content-length" => {
        guard not(self.body is Fixed(_)) else { raise BadRequest }
        guard parse_int(value, base=10) is Some(len) else { raise BadRequest }
        if self.body is Empty {
          self.body = Fixed(len)
        }
      }
      "transfer-encoding" => {
        guard not(self.body is Chunked(_)) else { raise BadRequest }
        guard value[:].to_lower_case() is "chunked" else {
          raise NotImplemented
        }
        self.body = Chunked(0)
      }
      _ => ()
    }
    self.transport.drop(line_end + 2)
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
pub async fn Reader::read_request(self : Reader) -> Request raise {
  guard self.body is Empty
  let request_line_end = self.transport.find("\r\n")
  let request_line = self.transport[:request_line_end]
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
    _ => abort("handle error")
  }
  let request_line = request_line[meth_len + 1:]
  guard request_line.find(" ") is Some(path_len) else { raise BadRequest }
  let path = request_line[:path_len].to_bytes()
  match request_line[path_len + 1:] {
    "HTTP/1.1" | "HTTP/1.0" => ()
    protocol =>
      raise HttpVersionNotSupported(@bytes_util.ascii_to_string(protocol))
  }
  self.transport.drop(request_line_end + 2)
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
pub async fn Reader::read_response(self : Reader) -> Response raise {
  guard self.body is Empty
  let response_line_end = self.transport.find("\r\n")
  let response_line = self.transport[:response_line_end]
  guard response_line.find(" ") is Some(protocol_len) else { raise BadRequest }
  match self.transport[:protocol_len] {
    "HTTP/1.1" | "HTTP/1.0" => ()
    protocol =>
      raise HttpVersionNotSupported(@bytes_util.ascii_to_string(protocol))
  }
  let response_line = response_line[protocol_len + 1:]
  guard response_line.find(" ") is Some(code_len) else { raise BadRequest }
  guard parse_int(response_line[:code_len], base=10) is Some(code) else {
    raise BadRequest
  }
  let reason = response_line[code_len + 1:].to_bytes()
  self.transport.drop(response_line_end + 2)
  let headers = self.read_headers()
  { code, reason, headers }
}

///|
/// Discard the body of current HTTP request/response,
/// so that the next request/response can be processed.
pub async fn Reader::skip_body(self : Reader) -> Unit raise {
  if self.body is (Empty | Fixed(0)) {
    return
  }
  let buf = FixedArray::make(1024, b'0')
  while self.read(buf) is n && n > 0 {

  }
}
