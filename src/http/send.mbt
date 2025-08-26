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
/// Specify the body of a HTTP request/response for sending. `Empty` means no body.
pub(all) enum Body {
  Empty
  Fixed(Bytes)
  Stream(&@io.Reader)
}

///|
async fn[Writer : @io.Writer] send_headers_and_body(
  w : Writer,
  headers : Array[Header],
  body : Body,
) -> Unit raise {
  for header in headers {
    let Header(k, v) = header
    w..write(k)..write(": ")..write(v)..write("\r\n")
  }
  match body {
    Empty => w.write("\r\n")
    Fixed(body) =>
      w
      ..write(b"Content-Length: ")
      ..write(encode_int(body.length(), base=10))
      ..write("\r\n\r\n")
      ..write(body)
    Stream(body) => {
      w.write(b"Transfer-Encoding: chunked\r\n\r\n")
      let buf = FixedArray::make(1024, b'0')
      while body.read(buf, offset=0, max_len=buf.length()) is n && n > 0 {
        w
        ..write(encode_int(n, base=16))
        ..write("\r\n")
        ..write(buf.unsafe_reinterpret_as_bytes()[:n])
        ..write("\r\n")
      } else {
        w.write("0\r\n\r\n")
      }
    }
  }
}

///|
/// Send a HTTP/1.1 request message through a writer.
pub async fn[Writer : @io.Writer] send_request(
  w : Writer,
  request : Request,
  body : Body,
) -> Unit raise {
  match request.meth {
    Get => w.write("GET ")
    Head => w.write("HEAD ")
    Post => w.write("POST ")
    Put => w.write("PUT ")
    Delete => w.write("DELETE ")
    Connect => w.write("CONNECT ")
    Options => w.write("OPTIONS ")
    Trace => w.write("TRACE ")
    Patch => w.write("PATCH ")
  }
  w..write(request.path)..write(" HTTP/1.1\r\n")
  send_headers_and_body(w, request.headers, body)
}

///|
/// Send a HTTP/1.1 request response through a writer.
pub async fn[Writer : @io.Writer] send_response(
  w : Writer,
  response : Response,
  body : Body,
) -> Unit raise {
  w
  ..write("HTTP/1.1 ")
  ..write(encode_int(response.code, base=10))
  ..write(" ")
  ..write(response.reason)
  ..write("\r\n")
  send_headers_and_body(w, response.headers, body)
}
