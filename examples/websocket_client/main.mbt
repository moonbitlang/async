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
/// WebSocket client example
/// 
/// This demonstrates how to connect to a WebSocket server,
/// send messages, and receive responses.
fn init {
  println("WebSocket client example")
}

///|
pub async fn connect_to_echo_server() -> Unit {
  println("Connecting to WebSocket echo server at localhost:8080")

  // Connect to the server
  let client = @websocket.Client::connect("localhost", "/ws", port=8080)
  println("Connected successfully!")

  // Send some test messages
  let test_messages = [
    "Hello, WebSocket!", "This is a test message", "MoonBit WebSocket client works!",
    "Final message",
  ]
  for message in test_messages {
    // Send text message
    println("Sending: \{message}")
    client.send_text(message)

    // Receive echo response
    let response = client.receive()
    match response {
      @websocket.Text(text) => println("Received: \{text}")
      @websocket.Binary(data) =>
        println("Received binary data (\{data.length()} bytes)")
    }
  }

  // Small delay between messages
  // Note: In a real implementation, you might want to add a sleep function
  // For now, we'll just continue immediately

  // Test binary message
  println("Sending binary data...")
  let binary_data = @encoding/utf8.encode("Binary test data")
  client.send_binary(binary_data)
  let binary_response = client.receive()
  match binary_response {
    @websocket.Text(text) => println("Received text response: \{text}")
    @websocket.Binary(data) =>
      println("Received binary response (\{data.length()} bytes)")
  }

  // Close the connection
  println("Closing connection...")
  client.close()
  println("Client example completed")
}
