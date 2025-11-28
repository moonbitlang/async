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
async test "websocket basic" {
  @async.with_task_group(group => {
    let server = @http.Server::new(@socket.Addr::parse("127.0.0.1:0"))
    let addr = server.addr()
    group.spawn_bg(() => {
      defer server.close()
      let (conn, _) = server.accept()
      let request = conn.read_request() catch {
        err => {
          conn.close()
          raise err
        }
      }
      let ws = @websocket.from_http_server(request, conn)
      defer ws.close()
      let msg = ws.recv()
      let msg_content = msg.read_all().text()
      inspect(msg.kind, content="Binary")
      inspect(msg_content, content="abcd")
      ws..start_message(msg.kind)..write(msg_content)..end_message()
      let msg = ws.recv()
      let msg_content = msg.read_all().text()
      inspect(msg.kind, content="Text")
      inspect(msg_content, content="abcd")
      ws..start_message(msg.kind)..write(msg_content)..end_message()
      try ws.recv() catch {
        err => inspect(err, content="ConnectionClosed(Normal, None)")
      } noraise {
        _ => raise Failure("expected error, but nothing happens")
      }
    })
    let client = @websocket.connect("ws://localhost:\{addr.port()}")
    defer client.close()
    client.send_binary("abcd")
    let msg = client.recv()
    inspect(msg.kind, content="Binary")
    inspect(msg.read_all().text(), content="abcd")
    client.send_text("abcd")
    let msg = client.recv()
    inspect(msg.kind, content="Text")
    inspect(msg.read_all().text(), content="abcd")
    client.send_close()
  })
}
