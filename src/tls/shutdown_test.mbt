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
async test "peer close connection" {
  @async.with_task_group(fn(root) {
    // server
    let server = @socket.TcpServer::new(@socket.Addr::parse("127.0.0.1:0"))
    let addr = server.addr()
    root.spawn_bg(fn() {
      defer server.close()
      let (conn, _) = server.accept()
      defer conn.close()
      let server = @tls.Tls::server(
        conn,
        private_key_file="test_keys/key.pem",
        private_key_type=PEM,
        certificate_file="test_keys/cert.pem",
        certificate_type=PEM,
      )
      defer server.close()
      inspect(server.read_all().text(), content="abcd")
      // close the underlying connection directly
    })
    // client
    root.spawn_bg(fn() {
      let conn = @socket.Tcp::connect(addr)
      defer conn.close()
      let client = @tls.Tls::client(conn, verify=false)
      defer client.close()
      client.write("abcd")
      @async.sleep(100)
      // the server already closed the connection
      client.shutdown()
    })
  })
}
