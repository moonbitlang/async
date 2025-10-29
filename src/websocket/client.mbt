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
/// WebSocket client connection
pub struct Client {
  conn : @socket.Tcp
  mut closed : Bool
}

///|
/// Connect to a WebSocket server
///
/// `host` - The hostname or IP address to connect to
/// `path` - The path to request (e.g., "/ws")
/// `port` - The port number (default: 80 for ws://, 443 for wss://)
/// `headers` - Additional HTTP headers to send during handshake
///
/// Example:
/// ```moonbit no-check
/// let ws = Client::connect("example.com", "/ws")
/// ```
pub async fn Client::connect(
  host : String,
  path : String,
  port? : Int = 80,
  headers? : Map[String, String] = {},
) -> Client {
  // Connect TCP socket
  let addr = @socket.Addr::parse("\{host}:\{port}")
  let conn = @socket.Tcp::connect(addr)

  // Send WebSocket handshake request
  let key = "dGhlIHNhbXBsZSBub25jZQ==" // In production, generate random key
  let request = "GET \{path} HTTP/1.1\r\n"
  conn.write(request)
  conn.write("Host: \{host}\r\n")
  conn.write("Upgrade: websocket\r\n")
  conn.write("Connection: Upgrade\r\n")
  conn.write("Sec-WebSocket-Key: \{key}\r\n")
  conn.write("Sec-WebSocket-Version: 13\r\n")

  // Write additional headers
  let mut extra_headers = ""
  headers.each(fn(header_name, header_value) {
    extra_headers = extra_headers + "\{header_name}: \{header_value}\r\n"
  })
  if extra_headers != "" {
    conn.write(extra_headers)
  }
  conn.write("\r\n")

  // Read and validate handshake response
  let response_line = conn.read_exactly(1024) // Read initial response
  let response_str = @encoding/utf8.decode(response_line)
  guard response_str.contains("101") &&
    response_str.contains("Switching Protocols") else {
    conn.close()
    raise InvalidHandshake
  }
  { conn, closed: false }
}

///|
/// Close the WebSocket connection
pub fn Client::close(self : Client) -> Unit {
  if not(self.closed) {
    self.conn.close()
    self.closed = true
  }
}

///|
/// Send a text message
pub async fn Client::send_text(self : Client, text : String) -> Unit {
  guard not(self.closed) else { raise ConnectionClosed }
  let payload = @encoding/utf8.encode(text)
  write_frame(self.conn, true, OpCode::Text, payload, true)
}

///|
/// Send a binary message
pub async fn Client::send_binary(self : Client, data : Bytes) -> Unit {
  guard not(self.closed) else { raise ConnectionClosed }
  write_frame(self.conn, true, OpCode::Binary, data, true)
}

///|
/// Send a ping frame
pub async fn Client::ping(self : Client, data? : Bytes = Bytes::new(0)) -> Unit {
  guard not(self.closed) else { raise ConnectionClosed }
  write_frame(self.conn, true, OpCode::Ping, data, true)
}

///|
/// Send a pong frame
pub async fn Client::pong(self : Client, data? : Bytes = Bytes::new(0)) -> Unit {
  guard not(self.closed) else { raise ConnectionClosed }
  write_frame(self.conn, true, OpCode::Pong, data, true)
}

///|
/// Receive a message from the WebSocket
/// Returns the complete message after assembling all frames
pub async fn Client::receive(self : Client) -> Message {
  guard not(self.closed) else { raise ConnectionClosed }
  let frames : Array[Frame] = []
  let mut first_opcode : OpCode? = None
  for {
    let frame = read_frame(self.conn)

    // Handle control frames immediately
    match frame.opcode {
      OpCode::Close => {
        self.closed = true
        raise ConnectionClosed
      }
      OpCode::Ping => {
        // Auto-respond to ping with pong
        self.pong(data=frame.payload)
        continue
      }
      OpCode::Pong =>
        // Ignore pong frames
        continue
      _ => ()
    }

    // Track the first opcode for message type
    if first_opcode is None {
      first_opcode = Some(frame.opcode)
    }
    frames.push(frame)

    // If this is the final frame, assemble the message
    if frame.fin {
      break
    }
  }

  // Assemble message from frames
  let total_size = frames.fold(init=0, fn(acc, f) { acc + f.payload.length() })
  let data = FixedArray::make(total_size, b'\x00')
  let mut offset = 0
  for frame in frames {
    let payload_arr = frame.payload.to_fixedarray()
    for i = 0; i < payload_arr.length(); i = i + 1 {
      data[offset + i] = payload_arr[i]
    }
    offset += payload_arr.length()
  }
  let message_type = match first_opcode {
    Some(OpCode::Text) => MessageType::Text
    Some(OpCode::Binary) => MessageType::Binary
    _ => MessageType::Binary // Default to binary
  }
  { mtype: message_type, data: data.unsafe_reinterpret_as_bytes() }
}
