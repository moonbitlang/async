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
async fn test_server(port : Int, log : &Logger) -> Unit {
  let addr = @socket.Addr::parse("127.0.0.1:\{port}")
  @http.run_server(addr, (conn, _) => {
    let buf = FixedArray::make(1024, b'\x00')
    for {
      let request = conn.read_request()
      log.write_string(
        "server received request: \{request.meth} \{request.path}\n",
      )
      while conn.read(buf) is n && n > 0 {
        let data = @encoding/utf8.decode(buf.unsafe_reinterpret_as_bytes()[:n])
        log.write_string("server received: \{data}")
      }
      conn.send_response(200, "OK")
      log.write_string("server: sending \{request.meth} response part 1\n")
      conn..write("\{request.meth} response part 1\n")..flush()
      @async.sleep(100)
      log.write_string("server: sending \{request.meth} response part 2\n")
      conn..write("\{request.meth} response part 2\n")..end_response()
    }
  })
}

///|
async test "request streaming" {
  let port = 4213
  let log = StringBuilder::new()
  @async.with_task_group(group => {
    group.spawn_bg(no_wait=true, () => test_server(port, log))
    let buf = FixedArray::make(1024, b'\x00')
    async fn fetch_response(client : @http.Client) {
      while client.read(buf) is n && n > 0 {
        let data = @encoding/utf8.decode(buf.unsafe_reinterpret_as_bytes()[:n])
        log.write_string("client received: \{data}")
      }
    }

    {
      log.write_string("client sending GET request\n")
      let (response, client) = @http.get_stream(
        "http://localhost/get",
        port~,
        body="GET data\n",
      )
      defer client.close()
      inspect(response.code, content="200")
      fetch_response(client)
    }
    {
      log.write_string("client sending PUT request\n")
      let client = @http.put_stream("http://localhost/put", port~)
      defer client.close()
      client.flush()
      @async.sleep(100)
      log.write_string("client: sending PUT data part 1\n")
      client..write("PUT data part 1\n")..flush()
      @async.sleep(100)
      log.write_string("client: sending PUT data part 2\n")
      client.write("PUT data part 2\n")
      let response = client.end_request()
      inspect(response.code, content="200")
      fetch_response(client)
    }
    {
      log.write_string("client sending POST request\n")
      let client = @http.post_stream("http://localhost/post", port~)
      defer client.close()
      client.flush()
      @async.sleep(100)
      log.write_string("client: sending POST data part 1\n")
      client..write("POST data part 1\n")..flush()
      @async.sleep(100)
      log.write_string("client: sending POST data part 2\n")
      client.write("POST data part 2\n")
      let response = client.end_request()
      inspect(response.code, content="200")
      fetch_response(client)
    }
    // give some time for the client to close,
    // so that the port occupied by the server can be reused immediately.
    @async.sleep(200)
  })
  inspect(
    log,
    content=(
      #|client sending GET request
      #|server received request: Get /get
      #|server received: GET data
      #|server: sending Get response part 1
      #|client received: Get response part 1
      #|server: sending Get response part 2
      #|client received: Get response part 2
      #|client sending PUT request
      #|server received request: Put /put
      #|client: sending PUT data part 1
      #|server received: PUT data part 1
      #|client: sending PUT data part 2
      #|server received: PUT data part 2
      #|server: sending Put response part 1
      #|client received: Put response part 1
      #|server: sending Put response part 2
      #|client received: Put response part 2
      #|client sending POST request
      #|server received request: Post /post
      #|client: sending POST data part 1
      #|server received: POST data part 1
      #|client: sending POST data part 2
      #|server received: POST data part 2
      #|server: sending Post response part 1
      #|client received: Post response part 1
      #|server: sending Post response part 2
      #|client received: Post response part 2
      #|
    ),
  )
}
