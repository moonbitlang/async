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
/// Simple WebSocket echo server example
/// 
/// This server accepts WebSocket connections on localhost:8080
/// and echoes back any messages it receives.
///
/// You can test it with a JavaScript client in a web browser:
/// ```javascript
/// const ws = new WebSocket('ws://localhost:8080');
/// ws.onopen = function() {
///     console.log('Connected');
///     ws.send('Hello, WebSocket!');
/// };
/// ws.onmessage = function(event) {
///     console.log('Received:', event.data);
/// };
/// ```
fn init {
  println("WebSocket echo server example")
}

///|
/// Start the WebSocket echo server
/// This function starts a server that listens on localhost:8080
/// and echoes back any messages it receives from clients
pub async fn start_echo_server() -> Unit {
  println("Starting WebSocket echo server on localhost:8080")
  @websocket.run_server(
    @socket.Addr::parse("127.0.0.1:8080"),
    "/ws",
    async fn(ws, client_addr) {
      println("New WebSocket connection from \{client_addr}")

      // Simple echo loop - receive and echo back
      // Connection errors will automatically close the handler
      try {
        for {
          let msg = ws.receive()
          match msg.mtype {
            @websocket.MessageType::Text => {
              let text = @encoding/utf8.decode(msg.data)
              println("Received text: \{text}")
              ws.send_text("Echo: " + text)
            }
            @websocket.MessageType::Binary => {
              println("Received binary data (\{msg.data.length()} bytes)")
              ws.send_binary(msg.data)
            }
          }
        }
      } catch {
        @websocket.ConnectionClosed =>
          println("Client \{client_addr} disconnected")
        e => println("Error with client \{client_addr}: \{e}")
      }
    },
    allow_failure=true,
  )
}
