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

/// WebSocket Demo Main
/// 
/// This demonstrates how to use the WebSocket API.
/// In a real application, you would use an async runtime to execute
/// the WebSocket server and client functions.

fn main {
  println("WebSocket Library Demo")
  println("=====================")
  println("")
  println("This library provides WebSocket client and server functionality.")
  println("")
  println("Server Example:")
  println("  Use @websocket.run_server() to create a WebSocket server")
  println("  Server accepts connections and handles WebSocket upgrade")
  println("")
  println("Client Example:")
  println("  Use @websocket.Client::connect() to connect to a server")
  println("  Send/receive text and binary messages")
  println("")
  println("For working examples, see:")
  println("  - examples/websocket_echo_server/")
  println("  - examples/websocket_client/")
  println("")
  println("Test with the included HTML client:")
  println("  - Open examples/websocket_echo_server/test_client.html")
  println("  - Connect to ws://localhost:8080")
}