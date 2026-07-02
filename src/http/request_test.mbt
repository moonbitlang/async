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
#cfg(any(target="native", target="js"))
async test "https request" {
  let (_, result) = @http.get("https://www.moonbitlang.com")
  assert_true(result.text().has_prefix("<!doctype html>"))
}

///|
#cfg(any(target="native", target="js"))
async test "http request" {
  let (_, result) = @http.get("http://www.example.org")
  assert_true(result.text().has_prefix("<!doctype html>"))
}

///|
#cfg(any(target="native", target="js"))
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

///|
#cfg(target="wasm")
async test "wasm http request" {
  let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  @async.with_task_group <| group => {
    group.spawn_bg(no_wait=true) <| () => {
      server.run_forever() <| ((req, _body, conn) => {
        inspect(req.path, content="/hello")
        conn
        ..send_response(200, "OK", extra_headers={ "Content-Length": "11" })
        ..write("hello wasm\n")
        .end_response()
      })
    }
    let (response, result) = @http.get(
      "http://localhost:\{server.addr.port()}/hello",
    )
    inspect(response.code, content="200")
    inspect(result.text(), content="hello wasm\n")
  }
}

///|
#cfg(target="wasm")
async fn wasm_https_test_tls_server(conn : @socket.Tcp) -> @tls.Tls {
  @tls.Tls::server(
    conn,
    private_key_file="test_keys/key.pem",
    private_key_type=PEM,
    certificate_file="test_keys/valid_server_cert.pem",
    certificate_type=PEM,
    pfx_file="test_keys/valid_server_cert.pfx",
  )
}

///|
#cfg(target="wasm")
async test "wasm https request" {
  let server = @socket.TcpServer(@socket.Addr::parse("127.0.0.1:0"))
  @async.with_task_group <| group => {
    group.spawn_bg(no_wait=true) <| () => {
      defer server.close()
      let (conn, _) = server.accept()
      defer conn.close()
      let tls = wasm_https_test_tls_server(conn)
      defer tls.close()
      guard tls.read_until("\r\n\r\n") is Some(request) else {
        raise Failure::Failure("missing request")
      }
      assert_true(request.has_prefix("GET /hello HTTP/1.1"))
      tls.write(
        b"HTTP/1.1 200 OK\r\nContent-Length: 12\r\nConnection: close\r\n\r\nhello https\n",
      )
      tls.shutdown() catch {
        _ => ()
      }
    }
    let client = @http.Client(
      "https://localhost:\{server.addr.port()}",
      trust=CustomPemFile("test_keys/valid_root_cert.pem"),
    )
    defer client.close()
    let response = client.get("/hello")
    inspect(response.code, content="200")
    inspect(client.read_all().text(), content="hello https\n")
  }
}
