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
fn log_headers(headers : Array[@http.Header], logger : &Logger) -> Unit {
  for header in headers {
    let Header(k, v) = header
    logger
    ..write_string(@bytes_util.ascii_to_string(k))
    ..write_string(": ")
    ..write_string(@bytes_util.ascii_to_string(v))
    ..write_string("\n")
  }
}

///|
fn log_request(req : @http.Request, logger : &Logger) -> Unit {
  logger
  ..write_object(req.meth)
  ..write_string(" ")
  ..write_object(@bytes_util.ascii_to_string(req.path))
  ..write_string("\n")
  log_headers(req.headers, logger)
}

///|
fn log_response(req : @http.Response, logger : &Logger) -> Unit {
  logger
  ..write_object(req.code)
  ..write_string(" ")
  ..write_object(@bytes_util.ascii_to_string(req.reason))
  ..write_string("\n")
  log_headers(req.headers, logger)
}

///|
test "read_request basic" {
  let log = StringBuilder::new()
  @async.with_event_loop(fn(root) {
    let (r, w) = @pipe.pipe()
    root.spawn_bg(fn() {
      defer w.close()
      @http.send_request(
        w,
        {
          meth: Get,
          path: "/",
          headers: [Header("Host", "x.y.org"), Header("User-Agent", "MoonBit")],
        },
        Empty,
      )
    })
    defer r.close()
    let input = @http.Reader::new(r)
    let request = input.read_request()
    log_request(request, log)
    log.write_string(input.read_all() |> @bytes_util.ascii_to_string)
  })
  inspect(
    log.to_string(),
    content=(
      #|Get "/"
      #|host: x.y.org
      #|user-agent: MoonBit
      #|
    ),
  )
}

///|
test "read_request fixed body" {
  let log = StringBuilder::new()
  @async.with_event_loop(fn(root) {
    let (r, w) = @pipe.pipe()
    root.spawn_bg(fn() {
      defer w.close()
      @http.send_request(
        w,
        {
          meth: Get,
          path: "/",
          headers: [Header("Host", "x.y.org"), Header("User-Agent", "MoonBit")],
        },
        Fixed(b"message"),
      )
    })
    defer r.close()
    let input = @http.Reader::new(r)
    let request = input.read_request()
    log_request(request, log)
    log.write_string(input.read_all() |> @bytes_util.ascii_to_string)
  })
  inspect(
    log.to_string(),
    content=(
      #|Get "/"
      #|host: x.y.org
      #|user-agent: MoonBit
      #|content-length: 7
      #|message
    ),
  )
}

///|
test "read_request chunked" {
  let log = StringBuilder::new()
  @async.with_event_loop(fn(root) {
    let (r, w) = @pipe.pipe()
    root.spawn_bg(fn() {
      defer w.close()
      let file = @fs.open("src/http/moon.pkg.json", mode=ReadOnly)
      defer file.close()
      @http.send_request(
        w,
        {
          meth: Get,
          path: "/",
          headers: [Header("Host", "x.y.org"), Header("User-Agent", "MoonBit")],
        },
        Stream(file),
      )
    })
    defer r.close()
    let input = @http.Reader::new(r)
    let request = input.read_request()
    log_request(request, log)
    log.write_string(input.read_all() |> @bytes_util.ascii_to_string)
  })
  inspect(
    log.to_string(),
    content=(
      #|Get "/"
      #|host: x.y.org
      #|user-agent: MoonBit
      #|transfer-encoding: chunked
      #|{
      #|  "import": [
      #|    "moonbitlang/async/io",
      #|    "moonbitlang/async/socket",
      #|    "moonbitlang/async/tls",
      #|    "moonbitlang/async/internal/bytes_util"
      #|  ],
      #|  "test-import": [
      #|    "moonbitlang/async",
      #|    "moonbitlang/async/pipe",
      #|    "moonbitlang/async/fs"
      #|  ]
      #|}
      #|
    ),
  )
}

///|
test "read_request stream" {
  let log = StringBuilder::new()
  @async.with_event_loop(fn(root) {
    let (r, w) = @pipe.pipe()
    let (r2, w2) = @pipe.pipe()
    root.spawn_bg(fn() {
      defer w.close()
      defer r2.close()
      @http.send_request(
        w,
        {
          meth: Get,
          path: "/",
          headers: [Header("Host", "x.y.org"), Header("User-Agent", "MoonBit")],
        },
        Stream(r2),
      )
    })
    root.spawn_bg(fn() {
      defer w2.close()
      @async.sleep(50)
      log.write_string("writing data...\n")
      w2.write("abcd")
      @async.sleep(50)
      log.write_string("writing data...\n")
      w2.write("efgh")
      @async.sleep(50)
      log.write_string("writing data...\n")
      w2.write("ijkl")
    })
    defer r.close()
    let input = @http.Reader::new(r)
    let request = input.read_request()
    log_request(request, log)
    let buf = FixedArray::make(1024, b'0')
    while input.read(buf) is n && n > 0 {
      let data = buf.unsafe_reinterpret_as_bytes()[:n]
        |> @bytes_util.ascii_to_string
      log.write_string("received \{data} from body\n")
    }
  })
  inspect(
    log.to_string(),
    content=(
      #|Get "/"
      #|host: x.y.org
      #|user-agent: MoonBit
      #|transfer-encoding: chunked
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
test "multiple request" {
  let log = StringBuilder::new()
  @async.with_event_loop(fn(root) {
    let (r, w) = @pipe.pipe()
    let (r2, w2) = @pipe.pipe()
    root.spawn_bg(fn() {
      defer w.close()
      defer r2.close()
      @http.send_request(
        w,
        {
          meth: Get,
          path: "/",
          headers: [Header("Host", "x.y.org"), Header("User-Agent", "MoonBit")],
        },
        Stream(r2),
      )
      @async.sleep(50)
      @http.send_request(
        w,
        {
          meth: Get,
          path: "/",
          headers: [Header("Host", "z.w.org"), Header("User-Agent", "MoonBit")],
        },
        Fixed("message2"),
      )
    })
    root.spawn_bg(fn() {
      defer w2.close()
      @async.sleep(50)
      log.write_string("writing data...\n")
      w2.write("abcd")
      @async.sleep(50)
      log.write_string("writing data...\n")
      w2.write("efgh")
      @async.sleep(50)
      log.write_string("writing data...\n")
      w2.write("ijkl")
    })
    defer r.close()
    let input = @http.Reader::new(r)
    let request = input.read_request()
    log_request(request, log)
    log
    ..write_string(input.read_all() |> @bytes_util.ascii_to_string)
    ..write_string("\n\n=========\n\n")
    let request = input.read_request()
    log_request(request, log)
    log
    ..write_string(input.read_all() |> @bytes_util.ascii_to_string)
    ..write_string("\n")
  })
  inspect(
    log.to_string(),
    content=(
      #|Get "/"
      #|host: x.y.org
      #|user-agent: MoonBit
      #|transfer-encoding: chunked
      #|writing data...
      #|writing data...
      #|writing data...
      #|abcdefghijkl
      #|
      #|=========
      #|
      #|Get "/"
      #|host: z.w.org
      #|user-agent: MoonBit
      #|content-length: 8
      #|message2
      #|
    ),
  )
}

///|
test "read_response basic" {
  let log = StringBuilder::new()
  @async.with_event_loop(fn(root) {
    let (r, w) = @pipe.pipe()
    root.spawn_bg(fn() {
      defer w.close()
      @http.send_response(
        w,
        { code: 200, reason: "OK", headers: [] },
        Fixed("message"),
      )
    })
    defer r.close()
    let input = @http.Reader::new(r)
    let response = input.read_response()
    log_response(response, log)
    log.write_string(input.read_all() |> @bytes_util.ascii_to_string)
  })
  inspect(
    log.to_string(),
    content=(
      #|200 "OK"
      #|content-length: 7
      #|message
    ),
  )
}
