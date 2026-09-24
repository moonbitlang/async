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
extend Reader with @io.Reader::{read_some, read_all}

///|
fn log_headers(headers : Headers, logger : &Logger) -> Unit {
  for k, v in headers {
    logger <+ "\{k}: \{v}\n"
  }
}

///|
fn log_request(req : Request, logger : &Logger) -> Unit {
  logger <+ "\{@debug.to_string(req.meth)} \{req.path}\n"
  log_headers(req.headers, logger)
}

///|
fn log_response(req : Response, logger : &Logger) -> Unit {
  logger <+ "\{req.code} \{req.reason}\n"
  log_headers(req.headers, logger)
}

///|
async test "read_request basic" {
  let log = StringBuilder()
  @async.with_task_group() <| root => {
    let (r, w) = @io.pipe()
    root.spawn_bg() <| () => {
      defer w.close()
      w
      ..write("GET / HTTP/1.1\r\n")
      ..write("Host: x.y.org\r\n")
      .write("User-Agent: MoonBit\r\n\r\n")
    }
    defer r.close()
    let input = Reader::new(r)
    let request = input.read_request()
    log_request(request, log)
    log.write_string(input.read_all().text())
  }
  inspect(
    log.to_string(),
    content=(
      #|Get /
      #|Host: x.y.org
      #|User-Agent: MoonBit
      #|
    ),
  )
}

///|
async test "read_request fixed body" {
  let log = StringBuilder()
  @async.with_task_group() <| root => {
    let (r, w) = @io.pipe()
    root.spawn_bg() <| () => {
      defer w.close()
      w
      ..write("GET / HTTP/1.1\r\n")
      ..write("Host: x.y.org\r\n")
      ..write("User-Agent: MoonBit\r\n")
      ..write("Content-Length: 7\r\n\r\n")
      .write("message")
    }
    defer r.close()
    let input = Reader::new(r)
    let request = input.read_request()
    log_request(request, log)
    log.write_string(input.read_all().text())
  }
  inspect(
    log.to_string(),
    content=(
      #|Get /
      #|Host: x.y.org
      #|User-Agent: MoonBit
      #|Content-Length: 7
      #|message
    ),
  )
}

///|
async test "read_request fixed body early EOF" {
  @async.with_task_group() <| root => {
    let (r, w) = @io.pipe()
    root.spawn_bg() <| () => {
      defer w.close()
      w
      ..write("GET / HTTP/1.1\r\n")
      ..write("Host: x.y.org\r\n")
      ..write("User-Agent: MoonBit\r\n")
      ..write("Content-Length: 8\r\n\r\n")
      .write("message")
    }
    defer r.close()
    let input = Reader::new(r)
    let _request = input.read_request()
    debug_inspect(
      @test_util.expect_error_async(() => input.read_all().binary()),
      content=(
        #|ReaderClosed
      ),
    )
  }
}

///|
async test "read_request chunked" {
  let log = StringBuilder()
  @async.with_task_group() <| root => {
    let (r, w) = @io.pipe()
    root.spawn_bg() <| () => {
      defer w.close()
      w
      ..write("GET / HTTP/1.1\r\n")
      ..write("Host: x.y.org\r\n")
      ..write("User-Agent: MoonBit\r\n")
      ..write("Transfer-Encoding: chunked\r\n\r\n")
      ..write("4\r\n")
      ..write("abcd\r\n")
      ..write("10\r\n")
      ..write("abcdefghijklmnop\r\n")
      .write("0\r\n\r\n")
    }
    defer r.close()
    let input = Reader::new(r)
    let request = input.read_request()
    log_request(request, log)
    log.write_string(input.read_all().text())
  }
  inspect(
    log.to_string(),
    content=(
      #|Get /
      #|Host: x.y.org
      #|User-Agent: MoonBit
      #|Transfer-Encoding: chunked
      #|abcdabcdefghijklmnop
    ),
  )
}

///|
async test "read_request stream" {
  let log = StringBuilder()
  @async.with_task_group() <| root => {
    let (r, w) = @io.pipe()
    root.spawn_bg() <| () => {
      defer w.close()
      w
      ..write("GET / HTTP/1.1\r\n")
      ..write("Host: x.y.org\r\n")
      ..write("User-Agent: MoonBit\r\n")
      .write("Transfer-Encoding: chunked\r\n\r\n")
      @async.sleep(50)
      log <+ "writing data...\n"
      w.write("4\r\nabcd\r\n")
      @async.sleep(50)
      log <+ "writing data...\n"
      w.write("4\r\nefgh\r\n")
      @async.sleep(50)
      log <+ "writing data...\n"
      w.write("4\r\nijkl\r\n")
      w.write("0\r\n\r\n")
    }
    defer r.close()
    let input = Reader::new(r)
    let request = input.read_request()
    log_request(request, log)
    while input.read_some() is Some(data) {
      let data = @utf8.decode(data)
      log.write_string("received \{data} from body\n")
    }
  }
  inspect(
    log.to_string(),
    content=(
      #|Get /
      #|Host: x.y.org
      #|User-Agent: MoonBit
      #|Transfer-Encoding: chunked
      #|writing data...
      #|received abcd from body
      #|writing data...
      #|received efgh from body
      #|writing data...
      #|received ijkl from body
      #|
    ),
  )
}

///|
async test "multiple request" {
  let log = StringBuilder()
  @async.with_task_group() <| root => {
    let (r, w) = @io.pipe()
    root.spawn_bg() <| () => {
      defer w.close()
      w
      ..write("GET / HTTP/1.1\r\n")
      ..write("Host: x.y.org\r\n")
      ..write("User-Agent: MoonBit\r\n")
      .write("Transfer-Encoding: chunked\r\n\r\n")
      @async.sleep(50)
      log <+ "writing data...\n"
      w.write("4\r\nabcd\r\n")
      @async.sleep(50)
      log <+ "writing data...\n"
      w.write("4\r\nefgh\r\n")
      @async.sleep(50)
      log <+ "writing data...\n"
      w.write("4\r\nijkl\r\n")
      w.write("0\r\n\r\n")
      @async.sleep(50)
      w
      ..write("GET / HTTP/1.1\r\n")
      ..write("Host: z.w.org\r\n")
      ..write("User-Agent: MoonBit\r\n")
      ..write("Content-Length: 8\r\n\r\n")
      .write("message2")
    }
    defer r.close()
    let input = Reader::new(r)
    let request = input.read_request()
    log_request(request, log)
    log..write_string(input.read_all().text()).write_string("\n\n=========\n\n")
    let request = input.read_request()
    log_request(request, log)
    log.write_string(input.read_all().text())
  }
  inspect(
    log.to_string(),
    content=(
      #|Get /
      #|Host: x.y.org
      #|User-Agent: MoonBit
      #|Transfer-Encoding: chunked
      #|writing data...
      #|writing data...
      #|writing data...
      #|abcdefghijkl
      #|
      #|=========
      #|
      #|Get /
      #|Host: z.w.org
      #|User-Agent: MoonBit
      #|Content-Length: 8
      #|message2
    ),
  )
}

///|
async test "empty header value" {
  @async.with_task_group() <| root => {
    let (r, w) = @io.pipe()
    root.spawn_bg() <| () => {
      defer w.close()
      w
      ..write("GET / HTTP/1.1\r\n")
      ..write("Empty1:\r\n")
      .write("Empty2: \r\n\r\n")
    }
    defer r.close()
    let input = Reader::new(r)
    let request = input.read_request()
    debug_inspect(
      request.headers,
      content=(
        #|{ "Empty1": "", "Empty2": "" }
      ),
    )
  }
}

///|
async test "read_response basic" {
  let log = StringBuilder()
  @async.with_task_group() <| root => {
    let (r, w) = @io.pipe()
    root.spawn_bg() <| () => {
      defer w.close()
      w
      ..write("HTTP/1.1 200 OK\r\n")
      ..write("Content-Length: 7\r\n\r\n")
      .write("message")
    }
    defer r.close()
    let input = Reader::new(r)
    let response = input.read_response(
      request_method=None,
      auto_decompress=true,
    )
    log_response(response, log)
    log.write_string(input.read_all().text())
  }
  inspect(
    log.to_string(),
    content=(
      #|200 OK
      #|Content-Length: 7
      #|message
    ),
  )
}

///|
async test "read_response passthrough fallback (no length headers)" {
  let log = StringBuilder()
  @async.with_task_group() <| root => {
    let (r, w) = @io.pipe()
    root.spawn_bg() <| () => {
      defer w.close()
      w
      ..write("HTTP/1.1 200 OK\r\n")
      ..write("Connection: close\r\n")
      ..write("Content-Type: text/plain\r\n\r\n")
      // No Content-Length or Transfer-Encoding
      // Body ends when connection closes
      .write("Hello, World!")
    }
    defer r.close()
    let input = Reader::new(r)
    let response = input.read_response(
      request_method=None,
      auto_decompress=true,
    )
    log_response(response, log)

    // Read body via PassThrough fallback (reads until EOF/connection close)
    log.write_string(input.read_all().text())
  }
  inspect(
    log.to_string(),
    content=(
      #|200 OK
      #|Connection: close
      #|Content-Type: text/plain
      #|Hello, World!
    ),
  )
}

///|
async test "read_response 204 No Content (no body)" {
  let log = StringBuilder()
  @async.with_task_group() <| root => {
    let (r, w) = @io.pipe()
    root.spawn_bg() <| () => {
      defer w.close()
      w
      ..write("HTTP/1.1 204 No Content\r\n")
      ..write("Connection: keep-alive\r\n")
      .write("Date: Mon, 15 Feb 2026 00:00:00 GMT\r\n\r\n")
      // 204 responses MUST NOT contain a message body
      // Connection remains open for next request
    }
    defer r.close()
    let input = Reader::new(r)
    let response = input.read_response(
      request_method=None,
      auto_decompress=true,
    )
    log_response(response, log)
    // Body should be Empty, not PassThrough
    let body_text = input.read_all().text()
    log <+ "body: "
    log.write_string(body_text)
  }
  inspect(
    log.to_string(),
    content=(
      #|204 No Content
      #|Connection: keep-alive
      #|Date: Mon, 15 Feb 2026 00:00:00 GMT
      #|body: 
    ),
  )
}

///|
async test "read_response 304 Not Modified (no body)" {
  let log = StringBuilder()
  @async.with_task_group() <| root => {
    let (r, w) = @io.pipe()
    root.spawn_bg() <| () => {
      defer w.close()
      w
      ..write("HTTP/1.1 304 Not Modified\r\n")
      ..write("Connection: keep-alive\r\n")
      ..write("ETag: \"abc123\"\r\n")
      .write("Cache-Control: max-age=3600\r\n\r\n")
      // 304 responses MUST NOT contain a message body
    }
    defer r.close()
    let input = Reader::new(r)
    let response = input.read_response(
      request_method=None,
      auto_decompress=true,
    )
    log_response(response, log)
    let body_text = input.read_all().text()
    log <+ "body: "
    log.write_string(body_text)
  }
  inspect(
    log.to_string(),
    content=(
      #|304 Not Modified
      #|Connection: keep-alive
      #|ETag: "abc123"
      #|Cache-Control: max-age=3600
      #|body: 
    ),
  )
}

///|
async test "read_response 100 Continue (no body)" {
  let log = StringBuilder()
  @async.with_task_group() <| root => {
    let (r, w) = @io.pipe()
    root.spawn_bg() <| () => {
      defer w.close()
      w
      ..write("HTTP/1.1 100 Continue\r\n")
      .write("\r\n")
      // 1xx responses MUST NOT contain a message body
    }
    defer r.close()
    let input = Reader::new(r)
    let response = input.read_response(
      request_method=None,
      auto_decompress=true,
    )
    log_response(response, log)
    let body_text = input.read_all().text()
    log <+ "body: "
    log.write_string(body_text)
  }
  inspect(
    log.to_string(),
    content=(
      #|100 Continue
      #|body: 
    ),
  )
}

///|
async test "read_response CONNECT 200 (no body, tunnel mode)" {
  let log = StringBuilder()
  @async.with_task_group() <| root => {
    let (r, w) = @io.pipe()
    root.spawn_bg() <| () => {
      defer w.close()
      w
      ..write("HTTP/1.1 200 Connection Established\r\n")
      .write("\r\n")
      // Successful CONNECT responses switch to tunnel mode
      // Connection remains open for tunneled traffic
    }
    defer r.close()
    let input = Reader::new(r)
    let response = input.read_response(
      request_method=Some(Connect),
      auto_decompress=true,
    )
    log_response(response, log)
    // Body should be Empty, not WaitConnectionClose
    let body_text = input.read_all().text()
    log <+ "body: "
    log.write_string(body_text)
  }
  inspect(
    log.to_string(),
    content=(
      #|200 Connection Established
      #|body: 
    ),
  )
}

///|
async test "read_response HEAD 200 (no body)" {
  let log = StringBuilder()
  @async.with_task_group() <| root => {
    let (r, w) = @io.pipe()
    root.spawn_bg() <| () => {
      defer w.close()
      w
      ..write("HTTP/1.1 200 OK\r\n")
      ..write("Content-Length: 1234\r\n")
      ..write("Content-Type: text/html\r\n")
      .write("\r\n")
      // HEAD responses never have a body, even with Content-Length
      // Connection remains open for next request
    }
    defer r.close()
    let input = Reader::new(r)
    let response = input.read_response(
      request_method=Some(Head),
      auto_decompress=true,
    )
    log_response(response, log)
    // Body should be Empty, not Fixed(1234)
    let body_text = input.read_all().text()
    log <+ "body: "
    log.write_string(body_text)
  }
  inspect(
    log.to_string(),
    content=(
      #|200 OK
      #|Content-Length: 1234
      #|Content-Type: text/html
      #|body: 
    ),
  )
}

///|
test "should_not_have_body" {
  inspect(should_not_have_body(None, 103), content="true")
  inspect(should_not_have_body(None, 200), content="false")
  inspect(should_not_have_body(None, 204), content="true")
  inspect(should_not_have_body(None, 205), content="false")
  inspect(should_not_have_body(None, 304), content="true")
  inspect(should_not_have_body(None, 404), content="false")
  inspect(should_not_have_body(Some(Head), 200), content="true")
  inspect(should_not_have_body(Some(Head), 404), content="true")
  inspect(should_not_have_body(Some(Head), 404), content="true")
  inspect(should_not_have_body(Some(Connect), 100), content="true")
  inspect(should_not_have_body(Some(Connect), 200), content="true")
  inspect(should_not_have_body(Some(Connect), 404), content="false")
}

///|
async test "gzip split between chunks" {
  let mut compressed = b""
  @async.with_task_group <| group => {
    let (r, w) = @io.pipe()
    group.spawn_bg() <| () => {
      defer w.close()
      @gzip_stream.Encoder(w)..write("A simple message to compress").end()
    }
    defer r.close()
    compressed = r.read_all().binary()
  }
  let (r, w) = @io.pipe()
  @async.with_task_group() <| group => {
    group.spawn_bg() <| () => {
      defer w.close()
      w
      ..write("HTTP/1.1 200 OK\r\n")
      ..write("Transfer-Encoding: Chunked\r\n")
      .write("Content-Encoding: gzip\r\n\r\n")
      for i in 0..<compressed.length() {
        w..write("1\r\n")..write(compressed[i:i + 1]).write("\r\n")
      }
      w.write("0\r\n\r\n")
    }
    defer r.close()
    let r = Reader::new(r)
    let response = r.read_response(
      request_method=Some(Get),
      auto_decompress=true,
    )
    inspect(response.code, content="200")
    inspect(
      r.read_all().text(),
      content=(
        #|A simple message to compress
      ),
    )
  }
}

///|
async test "fixed length gzip direct bytes one byte reads" {
  // This gzip stream reaches a state where the decoder can emit one more
  // byte from an already-decoded match copy without consuming new input.
  let compressed : Bytes = [
    // Gzip header (10 bytes) ends at 0x03.
    0x1f, 0x8b, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x03,
    // Deflate payload starts here. This fixed-Huffman block is the interesting
    // part: it sets up a match copy that outlives the first 1-byte read.
     0x4b, 0x4c, 0x4a, 0x4e, 0x24, 0x84, 0x00, 0xea, 0x16,
    // Gzip trailer starts here: CRC32 little-endian.
     0x01, 0xf1, 0x24,
    // ISIZE little-endian.
     0x00, 0x00, 0x00,
  ]
  let (r, w) = @io.pipe()
  @async.with_task_group() <| group => {
    group.spawn_bg() <| () => {
      defer w.close()
      w
      ..write("HTTP/1.1 200 OK\r\n")
      ..write("Content-Length: \{compressed.length()}\r\n")
      ..write("Content-Encoding: gzip\r\n")
      .write("\r\n")
      w.write(compressed)
    }
    defer r.close()
    let input = Reader::new(r)
    let response = input.read_response(
      request_method=None,
      auto_decompress=true,
    )
    inspect(response.code, content="200")
    let output = FixedArray::make(1, b'\x00')
    while input._direct_read(output, offset=0, max_len=1) > 0 {

    }
    inspect(true, content="true")
  }
}

///|
async test "read_response parse cookie" {
  @async.with_task_group() <| group => {
    let (r, w) = @io.pipe()
    group.spawn_bg() <| () => {
      defer w.close()
      w
      ..write("HTTP/1.1 200 OK\r\n")
      ..write("Set-Cookie: Cookie1=value1\r\n")
      ..write(
        "Set-Cookie: Cookie2=value2; Path=/path/to/xxx; Max-Age=420000; Secure\r\n",
      )
      ..write(
        "Set-Cookie: Cookie3=value3; Expires=Sun, 06 Nov 1994 08:49:37 GMT; Domain=example.moonbitlang.com; HttpOnly\r\n",
      )
      ..write("Set-Cookie: Cookie4=value four; ExtNoArg; ExtWithArg=xxx\r\n")
      .write("Content-Length: 0\r\n\r\n")
    }
    defer r.close()
    let input = Reader::new(r)
    let response = input.read_response(
      request_method=None,
      auto_decompress=true,
    )
    debug_inspect(
      response.cookies,
      content=(
        #|[
        #|  {
        #|    name: "Cookie1",
        #|    value: "value1",
        #|    path: None,
        #|    expires_raw: None,
        #|    max_age: None,
        #|    domain: None,
        #|    secure: false,
        #|    http_only: false,
        #|    extensions: [],
        #|  },
        #|  {
        #|    name: "Cookie2",
        #|    value: "value2",
        #|    path: Some("/path/to/xxx"),
        #|    expires_raw: None,
        #|    max_age: Some(420000),
        #|    domain: None,
        #|    secure: true,
        #|    http_only: false,
        #|    extensions: [],
        #|  },
        #|  {
        #|    name: "Cookie3",
        #|    value: "value3",
        #|    path: None,
        #|    expires_raw: Some("Sun, 06 Nov 1994 08:49:37 GMT"),
        #|    max_age: None,
        #|    domain: Some("example.moonbitlang.com"),
        #|    secure: false,
        #|    http_only: true,
        #|    extensions: [],
        #|  },
        #|  {
        #|    name: "Cookie4",
        #|    value: "value four",
        #|    path: None,
        #|    expires_raw: None,
        #|    max_age: None,
        #|    domain: None,
        #|    secure: false,
        #|    http_only: false,
        #|    extensions: ["ExtNoArg", "ExtWithArg=xxx"],
        #|  },
        #|]
      ),
    )
  }
}

///|
async test "chunk extension" {
  @async.with_task_group() <| root => {
    let (r, w) = @io.pipe()
    root.spawn_bg() <| () => {
      defer w.close()
      w
      ..write("HTTP/1.1 200 OK\r\n")
      ..write("Transfer-Encoding: chunked\r\n")
      ..write("\r\n")
      ..write("4;single_no_payload\r\nabcd\r\n")
      ..write("4;single_token_payload = value\r\nxyzw\r\n")
      ..write("4; single_quoted_payload=\"quoted\\\"\\\\\"\r\n1234\r\n")
      ..write("4;p1 ;p2=value; p3;p4=\"quoted\\\"\\\\\"\r\nABCD\r\n")
      ..write("0;last\r\n")
      .write("\r\n")
    }
    defer r.close()
    let input = Reader::new(r)
    // first message
    let response = input.read_response(
      request_method=None,
      auto_decompress=true,
    )
    inspect(response.code, content="200")
    debug_inspect(input.trailer, content="None")
    inspect(input.read_all().text(), content="abcdxyzw1234ABCD")
  }
}
