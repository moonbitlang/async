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
fnalias @http_file_server.(server, ascii_to_string)

///|
fn output_response(response : @http.Response, logger : &Logger) -> Unit {
  logger
  ..write_string("HTTP/1.1 ")
  ..write_object(response.code)
  ..write_string(" ")
  ..write_string(ascii_to_string(response.reason))
  ..write_string("\n")
  for header in response.headers {
    let Header(k, v) = header
    logger
    ..write_string(ascii_to_string(k))
    ..write_string(": ")
    ..write_string(ascii_to_string(v))
    ..write_string("\n")
  }
}

///|
let port = 4207

///|
async fn client(path : Bytes, logger : &Logger) -> Unit raise {
  let conn = @socket.TCP::connect(@socket.Addr::parse("127.0.0.1:\{port}"))
  defer conn.close()
  @http.send_request(conn, { meth: Get, path, headers: [] }, Empty)
  let src = @http.Reader::new(conn)
  let response = src.read_response()
  output_response(response, logger)
  logger.write_string(src.read_all() |> ascii_to_string)
}

///|
test "basic" {
  fn log(_) -> Unit {

  }

  let client_log = StringBuilder::new()
  @async.with_event_loop(fn(root) {
    root.spawn_bg(no_wait=true, () => server(root, path=b".", port~, log~))
    @async.sleep(50)
    client_log.write_string("client: GET /examples/http_file_server\n")
    client(b"/examples/http_file_server", client_log)
    client_log.write_string("\n\n")
    client_log.write_string(
      "client: GET /examples/http_file_server/moon.pkg.json\n",
    )
    client(b"/examples/http_file_server/moon.pkg.json", client_log)
    client_log.write_string("\n\n")
  })
  inspect(
    client_log,
    content=(
      #|client: GET /examples/http_file_server
      #|HTTP/1.1 200 OK
      #|content-type: text/html
      #|content-length: 547
      #|<!DOCTYPE html><html><head></head><body><h1>/examples/http_file_server</h1>\n<div style="margin: 1em; font-size: 15pt"><a href="/examples">..</a><br/><br/>\n<a href="/examples/http_file_server/main.mbt">main.mbt</a><br/>\n<a href="/examples/http_file_server/utils.mbt">utils.mbt</a><br/>\n<a href="/examples/http_file_server/moon.pkg.json">moon.pkg.json</a><br/>\n<a href="/examples/http_file_server/server_test.mbt">server_test.mbt</a><br/>\n<a href="/examples/http_file_server/http_file_server.mbti">http_file_server.mbti</a><br/>\n</div></body></html>
      #|
      #|client: GET /examples/http_file_server/moon.pkg.json
      #|HTTP/1.1 200 OK
      #|content-type: appliaction/octet-stream
      #|transfer-encoding: chunked
      #|{\n  "import": [\n    "moonbitlang/async",\n    "moonbitlang/async/io",\n    "moonbitlang/async/socket",\n    "moonbitlang/async/fs",\n    "moonbitlang/async/http"\n  ],\n  "is-main": true\n}\n
      #|
      #|
    ),
  )
}
