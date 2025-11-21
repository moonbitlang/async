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
async test "passthrough mode" {
  let log = []
  @async.with_task_group(group => {
    let server = @socket.TcpServer::new(@socket.Addr::parse("127.0.0.1:0"))
    let server_addr = server.addr()
    group.spawn_bg(() => {
      defer server.close()
      let (conn, _) = server.accept()
      let conn = @http.ServerConnection::new(conn)
      defer conn.close()
      let request = conn.read_request()
      inspect(request.meth, content="Connect")
      inspect(request.path, content="/path")
      conn..send_response(200, "OK")..end_response()
      conn.entre_passthrough_mode()
      while conn.read_some() is Some(packet) {
        let packet = @encoding/utf8.decode(packet)
        log.push("server received: \{packet}")
      }
    })
    let client = @http.Client::connect(
      "localhost",
      protocol=Http,
      port=server_addr.port(),
    )
    defer client.close()
    let response = client..request(Connect, "/path").end_request()
    inspect(response.code, content="200")
    client.entre_passthrough_mode()
    for packet in ["abcd", "efgh", "ijkl"] {
      log.push("client sending: \{packet}")
      client.write(packet)
      @async.sleep(200)
    }
  })
  @json.inspect(log, content=[
    "client sending: abcd", "server received: abcd", "client sending: efgh", "server received: efgh",
    "client sending: ijkl", "server received: ijkl",
  ])
}
