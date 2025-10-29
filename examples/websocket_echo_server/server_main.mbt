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

/// WebSocket Echo Server Example
/// 
/// This example shows how to create a simple WebSocket echo server
/// that listens on localhost:8080 and echoes back any messages received.
/// 
/// To test this server:
/// 1. Build and run this example
/// 2. Open test_client.html in a web browser
/// 3. Connect and send messages to see them echoed back

fn main {
  println("Starting WebSocket Echo Server...")
  
  // Since we can't directly use async in main, 
  // this shows how the server would be started
  println("To run the server, use an async runtime with:")
  println("  @websocket_echo_server.start_echo_server()")
  println("")
  println("Server will listen on: ws://localhost:8080")
  println("Open test_client.html in a browser to test")
}