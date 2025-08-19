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
fn to_lower_case(ident : @bytes.View) -> Bytes {
  let result = FixedArray::make(ident.length(), b'0')
  for i in 0..<ident.length() {
    match ident[i] {
      'A'..='Z' as b => result[i] = b - 'A' + 'a'
      b => result[i] = b
    }
  }
  result.unsafe_reinterpret_as_bytes()
}

///|
enum Cmd {
  Get
} derive(Show)

///|
struct HttpHeader {
  cmd : Cmd
  path : Bytes
  headers : Map[Bytes, Bytes]
} derive(Show)

///|
suberror InvalidRequest {
  UnsupportedMethod(String)
  InvalidProtocol(String)
  InvalidFormat
} derive(Show)

///|
typealias @io.BufferedReader[@socket.TCP] as Input

///|
async fn parse_http_request_line(src : Input) -> (Cmd, Bytes) raise {
  // parse the request line
  let cmd_len = src.find(b" ")
  let cmd = match src[:cmd_len] {
    b"GET" => Get
    cmd => raise UnsupportedMethod(ascii_to_string(cmd))
  }
  src.drop(cmd_len + 1)
  let uri_len = src.find(b" ")
  let uri = src[:uri_len]
  src.drop(uri_len + 1)
  let request_line_end = src.find(b"\r\n")
  let protocol = src[:request_line_end]
  src.drop(request_line_end + 2)
  guard protocol == b"HTTP/1.1" else {
    raise InvalidProtocol(ascii_to_string(protocol))
  }
  (cmd, uri)
}

///|
pub async fn parse_http_headers(src : Input) -> Map[Bytes, Bytes] raise {
  // parse request headers
  let headers = {}
  for {
    let line_end = src.find(b"\r\n")
    if line_end == 0 {
      // empty line indicates end of header
      src.drop(line_end + 2)
      break
    }
    let header_line = src[:line_end]
    guard header_line[:].find_index(':') is Some(colon_index) else {
      raise InvalidFormat
    }
    let key = to_lower_case(header_line[:colon_index])
    guard colon_index + 1 < header_line.length() else { raise InvalidFormat }
    let value_start = if header_line[colon_index + 1] == ' ' {
      colon_index + 2
    } else {
      colon_index + 1
    }
    let value = header_line[value_start:].to_bytes()
    headers[key] = value
    src.drop(line_end + 2)
  }
  headers
}

///|
async fn parse_http_request(src : Input) -> (HttpHeader, Bytes) raise {
  let (cmd, path) = parse_http_request_line(src)
  let headers = parse_http_headers(src)
  let body = match headers.get(b"content-length") {
    None => b""
    Some(len) => src.read_exactly(@strconv.parse_int(ascii_to_string(len)))
  }
  ({ cmd, path, headers }, body)
}
