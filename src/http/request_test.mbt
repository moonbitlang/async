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
async test "https request" {
  let (_, result) = @http.get("https://www.moonbitlang.com")
  assert_true(result.text().has_prefix("<!doctype html>"))
}

///|
async test "http request" {
  let (_, result) = @http.get("http://www.example.org")
  assert_true(result.text().has_prefix("<!doctype html>"))
}

///|
async test "request cancel" {
  let start = @env.now()
  let result = @async.with_timeout_opt(300, () => {
    @http.get(
      "https://cli.moonbitlang.com/binaries/latest/moonbit-linux-x86_64.tar.gz",
    )
  })
  let end = @env.now()
  assert_true(result is None)
  if @env.get_env_var("MOONBIT_ASYNC_TEST_SANITIZER_ENABLED") is None {
    let delta = end - start
    if delta >= 450 {
      raise Failure::Failure("request cancellation took too long: \{delta}ms")
    }
  }
}

///|
#cfg(target="native")
async test "manual Accept-Encoding" {
  let log = []
  let test_server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  @async.with_task_group <| group => {
    group.spawn_bg(no_wait=true) <| () => {
      test_server.run_forever() <| ((req, _body, conn) => {
        let accept_encoding = req.headers.get("accept-encoding")
        log.push("server received: \{to_repr(accept_encoding)}")
        let file = @fs.open("LICENSE", mode=ReadOnly)
        defer file.close()
        conn.send_response(200, "OK", extra_headers={
          "Content-Encoding": "gzip",
        })
        @gzip_stream.Encoder(conn)..write_reader(file).end()
        conn.end_response()
      })
    }
    let (_, result1) = @http.get("http://\{test_server.addr}")
    let (_, result2) = @http.get("http://\{test_server.addr}", headers={
      "Accept-Encoding": "gzip",
    })
    assert_not_eq(result1.binary().length(), result2.binary().length())
    json_inspect(log, content=[
      "server received: Some(\"gzip,identity\")", "server received: Some(\"gzip\")",
    ])
  }
}
