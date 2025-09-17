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
async fn[Writer : @io.Writer] send_headers(
  w : Writer,
  headers : Array[Header],
) -> Unit {
  for header in headers {
    let Header(k, v) = header
    w..write(k)..write(": ")..write(v)..write("\r\n")
  }
}

///|
async fn[Writer : @io.Writer] send_body_headers(
  w : Writer,
  body : Body,
) -> Unit {
  match body {
    Empty => ()
    Fixed(body) =>
      w
      ..write(b"Content-Length: ")
      ..write(encode_int(body.length(), base=10))
      ..write("\r\n")
    Stream(_) => w.write(b"Transfer-Encoding: chunked\r\n")
  }
}

///|
async fn[Writer : @io.Writer] send_body_chunked(
  w : Writer,
  buf : FixedArray[Byte],
  body : &@io.Reader,
) -> Unit {
  // Reserve enough space for chunk length and '\r\n' in the buffer,
  // so that we can commit the whole chunk in a single write to avoid small writes
  let max_len = buf.length() - 7
  while body.read(buf, offset=5, max_len~) is n && n > 0 {
    buf[5 + n] = '\r'
    buf[6 + n] = '\n'
    let len = encode_int(n, base=16)
    let start = 3 - len.length()
    buf[3] = '\r'
    buf[4] = '\n'
    buf.blit_from_bytes(start, len, 0, len.length())
    w.write(buf.unsafe_reinterpret_as_bytes()[start:n + 7])
  } else {
    w.write("0\r\n\r\n")
  }
}

///|
/// Send a HTTP/1.1 request message through a writer.
pub async fn[Writer : @io.Writer] send_request(
  w0 : Writer,
  request : Request,
  body : Body,
) -> Unit {
  let w = @io.BufferedWriter::new(w0)
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
  send_headers(w, request.headers)
  send_body_headers(w, body)
  w.write("\r\n")
  w.flush()
  match body {
    Empty => ()
    Fixed(body) => w0.write(body)
    Stream(body) => {
      let buf = FixedArray::make(1024, b'0')
      send_body_chunked(w0, buf, body)
    }
  }
}

///|
/// Send a HTTP/1.1 request response through a writer.
pub async fn[Writer : @io.Writer] send_response(
  w0 : Writer,
  response : Response,
  body : Body,
) -> Unit {
  let w = @io.BufferedWriter::new(w0)
  w
  ..write("HTTP/1.1 ")
  ..write(encode_int(response.code, base=10))
  ..write(" ")
  ..write(response.reason)
  ..write("\r\n")
  send_headers(w, response.headers)
  send_body_headers(w, body)
  w.write("\r\n")
  w.flush()
  match body {
    Empty => ()
    Fixed(body) => w0.write(body)
    Stream(body) => {
      let buf = FixedArray::make(1024, b'0')
      send_body_chunked(w0, buf, body)
    }
  }
}
