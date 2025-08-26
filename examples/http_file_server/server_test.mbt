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
struct Response {
  response_line : Bytes
  headers : Map[Bytes, Bytes]
  body : Bytes
}

///|
impl Show for Response with output(response, logger) {
  logger
  ..write_string(ascii_to_string(response.response_line))
  ..write_char('\n')
  for k, v in response.headers {
    logger
    ..write_string(ascii_to_string(k))
    ..write_string(": ")
    ..write_string(ascii_to_string(v))
    ..write_char('\n')
  }
  logger..write_char('\n')..write_string(ascii_to_string(response.body))
}

///|
async fn parse_reply(src : @io.BufferedReader[@socket.TCP]) -> Response raise {
  let response_line_len = src.find(b"\r\n")
  let response_line = src[:response_line_len]
  src.drop(response_line_len + 2)
  let headers = parse_http_headers(src)
  if headers.get(b"content-length") is Some(len) {
    let len = @strconv.parse_int(ascii_to_string(len))
    let body = src.read_exactly(len)
    { response_line, headers, body }
  } else if headers.get(b"transfer-encoding") is Some("chunked") {
    let body = @buffer.new()
    for {
      let len_end = src.find(b"\r\n")
      let len = @strconv.parse_int(base=16, ascii_to_string(src[:len_end]))
      src.drop(len_end + 2)
      body.write_bytes(src.read_exactly(len))
      src.drop(2)
      if len == 0 {
        break
      }
    }
    { response_line, headers, body: body.contents() }
  } else {
    { response_line, headers, body: "" }
  }
}

///|
let port = 4207

///|
async fn client(path : Bytes) -> Response raise {
  let conn = @socket.TCP::connect(@socket.Addr::parse("127.0.0.1:\{port}"))
  defer conn.close()
  conn..write(b"GET ")..write(path)..write(b" HTTP/1.1\r\n\r\n")
  parse_reply(@io.BufferedReader::new(conn))
}

///|
test "basic" {
  fn log(_) -> Unit {

  }

  let client_log = StringBuilder::new()
  @async.with_event_loop(fn(root) {
    root.spawn_bg(no_wait=true, () => server(root, path=b".", port~, log~))
    @async.sleep(50)
    client_log.write_string("client: GET /src\n")
    client_log.write_object(client(b"/src"))
    client_log.write_string("\n\n")
    client_log.write_string(
      "client: GET /examples/http_file_server/moon.pkg.json\n",
    )
    client_log.write_object(
      client(b"/examples/http_file_server/moon.pkg.json"),
    )
    client_log.write_string("\n\n")
  })
  inspect(
    client_log,
    content=(
      #|client: GET /src
      #|HTTP/1.1 200 OK
      #|content-type: text/html
      #|content-length: 1659
      #|
      #|<!DOCTYPE html><html><head></head><body><h1>/src</h1>\n<div style="margin: 1em; font-size: 15pt"><a href="/">..</a><br/><br/>\n<a href="/src/fs">fs</a><br/>\n<a href="/src/io">io</a><br/>\n<a href="/src/tls">tls</a><br/>\n<a href="/src/pipe">pipe</a><br/>\n<a href="/src/aqueue">aqueue</a><br/>\n<a href="/src/socket">socket</a><br/>\n<a href="/src/process">process</a><br/>\n<a href="/src/internal">internal</a><br/>\n<a href="/src/os_error">os_error</a><br/>\n<a href="/src/task.mbt">task.mbt</a><br/>\n<a href="/src/async.mbt">async.mbt</a><br/>\n<a href="/src/async.mbti">async.mbti</a><br/>\n<a href="/src/moon.pkg.json">moon.pkg.json</a><br/>\n<a href="/src/wait_test.mbt">wait_test.mbt</a><br/>\n<a href="/src/pause_test.mbt">pause_test.mbt</a><br/>\n<a href="/src/retry_test.mbt">retry_test.mbt</a><br/>\n<a href="/src/spawn_test.mbt">spawn_test.mbt</a><br/>\n<a href="/src/task_group.mbt">task_group.mbt</a><br/>\n<a href="/src/timer_test.mbt">timer_test.mbt</a><br/>\n<a href="/src/worker_test.mbt">worker_test.mbt</a><br/>\n<a href="/src/no_wait_test.mbt">no_wait_test.mbt</a><br/>\n<a href="/src/spawn_loop_test.mbt">spawn_loop_test.mbt</a><br/>\n<a href="/src/group_defer_test.mbt">group_defer_test.mbt</a><br/>\n<a href="/src/cancellation_test.mbt">cancellation_test.mbt</a><br/>\n<a href="/src/with_timeout_test.mbt">with_timeout_test.mbt</a><br/>\n<a href="/src/allow_failure_test.mbt">allow_failure_test.mbt</a><br/>\n<a href="/src/missing_close_test.mbt">missing_close_test.mbt</a><br/>\n<a href="/src/return_immediately_test.mbt">return_immediately_test.mbt</a><br/>\n<a href="/src/protect_from_cancel_test.mbt">protect_from_cancel_test.mbt</a><br/>\n</div></body></html>
      #|
      #|client: GET /examples/http_file_server/moon.pkg.json
      #|HTTP/1.1 200 OK
      #|transfer-encoding: chunked
      #|content-type: appliaction/octet-stream
      #|
      #|{\n  "import": [\n    "moonbitlang/async",\n    "moonbitlang/async/io",\n    "moonbitlang/async/socket",\n    "moonbitlang/async/fs"\n  ],\n  "is-main": true\n}\n
      #|
      #|


    ),
  )
}
