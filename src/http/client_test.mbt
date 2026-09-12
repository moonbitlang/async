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
#cfg(target="js")
async test "responses with null Web API bodies are empty readable streams" {
  let log = StringBuilder()
  @async.with_task_group() <| group => {
    let port = test_server(group, log)
    let client = @http.Client("http://localhost:\{port}")
    defer client.close()
    for
      request in [
        (@http.Get, "/no-content", 204),
        (@http.Get, "/reset-content", 205),
        (@http.Get, "/not-modified", 304),
        (@http.Head, "/head", 200),
      ] {
      let (meth, path, expected_status) = request
      client.request(meth, path)
      let response = client.end_request()
      assert_eq(response.code, expected_status)
      assert_eq(client.read_all().text(), "")
    }
  }
}

///|
#cfg(not(target="js"))
let is_js : Bool = false

///|
#cfg(target="js")
let is_js : Bool = true

///|
async test "request streaming" {
  let log = StringBuilder()
  @async.with_task_group() <| group => {
    let port = test_server(group, log)
    async fn fetch_response(client : @http.Client) {
      while client.read_some() is Some(data) {
        let data = @utf8.decode(data)
        log.write_string("client received: \{data}")
      }
    }

    {
      log <+ "client sending GET request\n"
      let (response, client) = @http.get_stream(
        "http://localhost:\{port}/get-streaming",
      )
      defer client.close()
      inspect(response.code, content="200")
      fetch_response(client)
    }
    {
      log <+ "client sending PUT request\n"
      let client = @http.put_stream("http://localhost:\{port}/put-streaming")
      defer client.close()
      @async.sleep(100)
      log <+ "client: sending PUT data part 1\n"
      client..write("PUT data part 1\n").flush()
      @async.sleep(100)
      log <+ "client: sending PUT data part 2\n"
      client.write("PUT data part 2\n")
      let response = client.end_request()
      inspect(response.code, content="200")
      fetch_response(client)
    }
    {
      log <+ "client sending POST request\n"
      let client = @http.post_stream("http://localhost:\{port}/post-streaming")
      defer client.close()
      @async.sleep(100)
      log <+ "client: sending POST data part 1\n"
      client..write("POST data part 1\n").flush()
      @async.sleep(100)
      log <+ "client: sending POST data part 2\n"
      client.write("POST data part 2\n")
      let response = client.end_request()
      inspect(response.code, content="200")
      fetch_response(client)
    }
    // give some time for the client to close,
    // so that the port occupied by the server can be reused immediately.
    @async.sleep(200)
  }
  if is_js {
    // On JS backend, streaming request body is not supported,
    // so we can only buffer the whole request body before sending.
    // This will result is different evaluation order behavior here.
    inspect(
      log,
      content=(
        #|client sending GET request
        #|server received request: GET /get-streaming
        #|server: sending GET response part 1
        #|client received: GET response part 1
        #|server: sending GET response part 2
        #|client received: GET response part 2
        #|client sending PUT request
        #|client: sending PUT data part 1
        #|client: sending PUT data part 2
        #|server received request: PUT /put-streaming
        #|server received: PUT data part 1
        #|PUT data part 2
        #|server: sending PUT response part 1
        #|client received: PUT response part 1
        #|server: sending PUT response part 2
        #|client received: PUT response part 2
        #|client sending POST request
        #|client: sending POST data part 1
        #|client: sending POST data part 2
        #|server received request: POST /post-streaming
        #|server received: POST data part 1
        #|POST data part 2
        #|server: sending POST response part 1
        #|client received: POST response part 1
        #|server: sending POST response part 2
        #|client received: POST response part 2
        #|
      ),
    )
  } else {
    inspect(
      log,
      content=(
        #|client sending GET request
        #|server received request: GET /get-streaming
        #|server: sending GET response part 1
        #|client received: GET response part 1
        #|server: sending GET response part 2
        #|client received: GET response part 2
        #|client sending PUT request
        #|client: sending PUT data part 1
        #|server received request: PUT /put-streaming
        #|server received: PUT data part 1
        #|client: sending PUT data part 2
        #|server received: PUT data part 2
        #|server: sending PUT response part 1
        #|client received: PUT response part 1
        #|server: sending PUT response part 2
        #|client received: PUT response part 2
        #|client sending POST request
        #|client: sending POST data part 1
        #|server received request: POST /post-streaming
        #|server received: POST data part 1
        #|client: sending POST data part 2
        #|server received: POST data part 2
        #|server: sending POST response part 1
        #|client received: POST response part 1
        #|server: sending POST response part 2
        #|client received: POST response part 2
        #|
      ),
    )
  }
}

///|
async test "multiple request" {
  let client = @http.Client("https://www.moonbitlang.com")
  defer client.close()
  let response1 = client.get("/")
  inspect(response1.code, content="200")
  assert_true(client.read_all().text().has_prefix("<!doctype html>"))
  let response2 = client.get("/download")
  inspect(response2.code, content="200")
  assert_true(client.read_all().text().has_prefix("<!doctype html>"))
}

///|
#cfg(any(target="native", target="wasm"))
async test "user agent" {
  let log = StringBuilder()
  @async.with_task_group() <| group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    let port = server.addr.port()
    group.spawn_bg(no_wait=true) <| () => {
      server.run_forever() <| ((request, _body, conn) => {
        let meth = @debug.to_string(request.meth).to_upper()
        log <+ "server received request: \{meth} \{request.path}\n"
        let ua = request.headers.get("user-agent").unwrap_or("none")
        log <+ "User-Agent: \{ua}\n"
        conn.send_response(200, "OK")
      })
    }
    {
      let (response, client) = @http.get_stream("http://localhost:\{port}")
      defer client.close()
      inspect(response.code, content="200")
    }
    let (response, client) = @http.get_stream("http://localhost:\{port}", headers={
      "User-Agent": "my-custom-UA/4.2",
    })
    defer client.close()
    inspect(response.code, content="200")
  }
  inspect(
    log.to_string(),
    content=(
      #|server received request: GET /
      #|User-Agent: moonbit-http-client/1.1
      #|server received request: GET /
      #|User-Agent: my-custom-UA/4.2
      #|
    ),
  )
}
