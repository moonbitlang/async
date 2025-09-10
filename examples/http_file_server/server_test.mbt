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
async fn client(
  path : Bytes,
  logger : &Logger,
  handle_response? : async (@http.Reader) -> Unit raise,
) -> Unit raise {
  let conn = @socket.TCP::connect(@socket.Addr::parse("127.0.0.1:\{port}"))
  defer conn.close()
  @http.send_request(conn, { meth: Get, path, headers: [] }, Empty)
  let src = @http.Reader::new(conn)
  let response = src.read_response()
  output_response(response, logger)
  match handle_response {
    None => logger.write_string(src.read_all() |> ascii_to_string)
    Some(f) => f(src)
  }
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
    let tmp_file_name = b"examples/test.zip"
    let tmp_file = @fs.create(tmp_file_name, permission=0o644)
    client(b"/examples/http_file_server?download_zip", client_log, handle_response=out => tmp_file.write_reader(
      out,
    ))
    tmp_file.close()
    let (r, w) = @process.read_from_process()
    defer r.close()
    root.spawn_bg(fn() {
      @process.run("unzip", ["-l", tmp_file_name], stdout=w) |> ignore
    })
    let from_unzip = @io.BufferedReader::new(r)
    let zip_content = []
    for i = 0; ; i = i + 1 {
      let eol = from_unzip.find("\n") catch {
        @io.ReaderClosed => break
        err => raise err
      }
      let line = from_unzip[:eol]
      from_unzip.drop(eol + 1)
      guard line.rev_find(" ") is Some(i) else {
        fail("invalid output from `unzip`")
      }
      let last_word = ascii_to_string(line[i + 1:].to_bytes())
      if last_word.has_prefix("examples/http_file_server") {
        zip_content.push(last_word)
      }
    }
    zip_content.sort()
    for file in zip_content {
      client_log..write_string(file)..write_string("\n")
    }
    @fs.remove(tmp_file_name)
  })
  inspect(
    client_log,
    content=(
      #|client: GET /examples/http_file_server
      #|HTTP/1.1 200 OK
      #|content-type: text/html
      #|content-length: 627
      #|<!DOCTYPE html><html><head></head><body><h1>/examples/http_file_server</h1>
      #|<div style="margin: 1em; font-size: 15pt"><a href="/examples/http_file_server?download_zip">download as zip</a><br/><br/>
      #|<a href="/examples">..</a><br/><br/>
      #|<a href="/examples/http_file_server/main.mbt">main.mbt</a><br/>
      #|<a href="/examples/http_file_server/utils.mbt">utils.mbt</a><br/>
      #|<a href="/examples/http_file_server/moon.pkg.json">moon.pkg.json</a><br/>
      #|<a href="/examples/http_file_server/server_test.mbt">server_test.mbt</a><br/>
      #|<a href="/examples/http_file_server/http_file_server.mbti">http_file_server.mbti</a><br/>
      #|</div></body></html>
      #|
      #|client: GET /examples/http_file_server/moon.pkg.json
      #|HTTP/1.1 200 OK
      #|content-type: appliaction/octet-stream
      #|transfer-encoding: chunked
      #|{
      #|  "import": [
      #|    "moonbitlang/async",
      #|    "moonbitlang/async/io",
      #|    "moonbitlang/async/socket",
      #|    "moonbitlang/async/fs",
      #|    "moonbitlang/async/http",
      #|    "moonbitlang/async/pipe",
      #|    "moonbitlang/async/process"
      #|  ],
      #|  "is-main": true
      #|}
      #|
      #|
      #|HTTP/1.1 200 OK
      #|content-type: application/octet-stream
      #|content-disposition: filename=http_file_server.zip
      #|transfer-encoding: chunked
      #|examples/http_file_server/
      #|examples/http_file_server/main.mbt
      #|examples/http_file_server/utils.mbt
      #|examples/http_file_server/moon.pkg.json
      #|examples/http_file_server/server_test.mbt
      #|examples/http_file_server/http_file_server.mbti
      #|
    ),
  )
}
