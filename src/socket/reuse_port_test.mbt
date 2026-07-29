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
// SO_REUSEPORT is a no-op on Windows, so the shared-port bind below only
// applies where the option exists; this test is compiled out on Windows.
#cfg(not(platform="windows"))
async test "reuse port" {
  @async.with_task_group() <| group => {
    let server1 = @socket.TcpServer(
      @socket.Addr::parse("127.0.0.1:0"),
      reuse_port=true,
    )
    let addr = server1.addr
    // A second server binds the same port while the first is still open.
    // This only succeeds because SO_REUSEPORT is enabled; without it the
    // bind would raise with "address already in use".
    let server2 = @socket.TcpServer(addr, reuse_port=true)
    // Close the first server so the exchange below deterministically goes
    // to server2, which is now the only socket listening on that port.
    server1.close()
    let server = group.spawn(() => {
      defer server2.close()
      let (conn, _) = server2.accept()
      defer conn.close()
      conn.write("ok")
    })
    let client = group.spawn(() => {
      let conn = @socket.Tcp::connect(addr)
      defer conn.close()
      conn.read_all().text()
    })
    server.wait()
    inspect(client.wait(), content="ok")
  }
}
