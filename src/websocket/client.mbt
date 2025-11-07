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
struct Client {
  conn : @socket.Tcp
  mut closed : CloseCode?
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
    raise InvalidHandshake(
      "Server did not respond with 101 Switching Protocols",
    )
  }

  // Basic validation that the response looks like a proper WebSocket upgrade
  guard response_str.contains("websocket") else {
    conn.close()
    raise InvalidHandshake(
      "Server response does not contain websocket upgrade confirmation",
    )
  }
  { conn, closed: None }
}

///|
/// Close the WebSocket connection
pub fn Client::close(self : Client) -> Unit {
  if self.closed is None {
    self.conn.close()
    self.closed = Some(Normal)
  }
}

///|
/// Send a text message
pub async fn Client::send_text(self : Client, text : String) -> Unit {
  if self.closed is Some(code) {
    raise ConnectionClosed(code)
  }
  let payload = @encoding/utf8.encode(text)
  write_frame(self.conn, true, OpCode::Text, payload, true)
}

///|
/// Send a binary message
pub async fn Client::send_binary(self : Client, data : Bytes) -> Unit {
  if self.closed is Some(code) {
    raise ConnectionClosed(code)
  }
  write_frame(self.conn, true, OpCode::Binary, data, true)
}

///|
/// Send a ping frame
/// 
/// TODO : it should be able to return a boolean 
/// indicating if a pong was received within a timeout
async fn Client::_ping(self : Client, data? : Bytes = Bytes::new(0)) -> Unit {
  if self.closed is Some(code) {
    raise ConnectionClosed(code)
  }
  write_frame(self.conn, true, OpCode::Ping, data, true)
}

///|
/// Send a pong frame
/// 
/// This is done automatically, so it is not exposed in the public API
async fn Client::pong(self : Client, data? : Bytes = Bytes::new(0)) -> Unit {
  if self.closed is Some(code) {
    raise ConnectionClosed(code)
  }
  write_frame(self.conn, true, OpCode::Pong, data, true)
}

///|
/// Receive a message from the WebSocket
/// Returns the complete message after assembling all frames
pub async fn Client::receive(self : Client) -> Message {
  if self.closed is Some(code) {
    raise ConnectionClosed(code)
  }
  let frames : Array[Frame] = []
  let mut first_opcode : OpCode? = None
  for {
    let frame = read_frame(self.conn)

    // Handle control frames immediately
    match frame.opcode {
      OpCode::Close => {
        // Parse close code and reason
        let mut close_code = Normal
        if frame.payload.length() >= 2 {
          let payload_arr = frame.payload.to_fixedarray()
          let code_int = (payload_arr[0].to_int() << 8) |
            payload_arr[1].to_int()
          close_code = CloseCode::from_int(code_int).unwrap_or(Normal)
          // Reason is parsed but not used in client close handling
          // let mut reason = ""
          // if frame.payload.length() > 2 {
          //   let reason_bytes = FixedArray::make(frame.payload.length() - 2, b'\x00')
          //   for i = 2; i < frame.payload.length(); i = i + 1 {
          //     reason_bytes[i - 2] = payload_arr[i]
          //   }
          //   reason = @encoding/utf8.decode_lossy(reason_bytes.unsafe_reinterpret_as_bytes())
          // }
        }
        self.closed = Some(close_code)
        raise ConnectionClosed(close_code)
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
  let message_data = data.unsafe_reinterpret_as_bytes()
  match first_opcode {
    Some(OpCode::Text) => Text(@encoding/utf8.decode_lossy(message_data))
    Some(OpCode::Binary) => Binary(message_data)
    _ => Binary(message_data)
  }
}
