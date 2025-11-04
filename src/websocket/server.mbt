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
/// WebSocket server connection
pub struct ServerConnection {
  conn : @socket.Tcp
  mut closed : Bool
}

///|
/// Handle WebSocket handshake on raw TCP connection - internal use
/// This performs the full HTTP upgrade handshake
async fn ServerConnection::handshake(conn : @socket.Tcp) -> ServerConnection? {
  // Read HTTP request
  let request_data = conn.read_exactly(4096) // Read reasonable amount
  let request_str = @encoding/utf8.decode(request_data)

  // Parse request line and headers
  let lines = request_str.split("\r\n").to_array()
  if lines.length() == 0 {
    return None
  }
  let request_line = lines[0]
  if not(request_line.contains("GET")) || not(request_line.contains("HTTP/1.1")) {
    return None
  }

  // Parse headers
  let headers : Map[String, String] = {}
  for i = 1; i < lines.length(); i = i + 1 {
    let line = lines[i]
    if line.is_empty() {
      break
    }
    if line.contains(":") {
      let parts = line.split(":").to_array()
      if parts.length() >= 2 {
        let key = parts[0].trim(chars=" \t").to_string()
        let value = parts[1].trim(chars=" \t").to_string()
        headers[key] = value
      }
    }
  }

  // Validate WebSocket handshake headers
  guard headers.get("Upgrade") is Some(upgrade) &&
    upgrade.to_lower() == "websocket" else {
    return None
  }
  guard headers.get("Connection") is Some(connection) &&
    connection.to_lower().contains("upgrade") else {
    return None
  }
  guard headers.get("Sec-WebSocket-Version") is Some(version) && version == "13" else {
    return None
  }
  guard headers.get("Sec-WebSocket-Key") is Some(key) else { return None }

  // Generate accept key
  let accept_key = generate_accept_key(key)

  // Send upgrade response
  let response = "HTTP/1.1 101 Switching Protocols\r\n" +
    "Upgrade: websocket\r\n" +
    "Connection: Upgrade\r\n" +
    "Sec-WebSocket-Accept: \{accept_key}\r\n" +
    "\r\n"
  conn.write(@encoding/utf8.encode(response))
  Some({ conn, closed: false })
}

///|
/// Close the WebSocket connection
pub fn ServerConnection::close(self : ServerConnection) -> Unit {
  if not(self.closed) {
    self.conn.close()
    self.closed = true
  }
}

///|
/// Send a text message
pub async fn ServerConnection::send_text(
  self : ServerConnection,
  text : String,
) -> Unit {
  guard not(self.closed) else { raise ConnectionClosed }
  let payload = @encoding/utf8.encode(text)
  write_frame(self.conn, true, OpCode::Text, payload, false)
}

///|
/// Send a binary message
pub async fn ServerConnection::send_binary(
  self : ServerConnection,
  data : Bytes,
) -> Unit {
  guard not(self.closed) else { raise ConnectionClosed }
  write_frame(self.conn, true, OpCode::Binary, data, false)
}

///|
/// Send a ping frame
pub async fn ServerConnection::ping(
  self : ServerConnection,
  data? : Bytes = Bytes::new(0),
) -> Unit {
  guard not(self.closed) else { raise ConnectionClosed }
  write_frame(self.conn, true, OpCode::Ping, data, false)
}

///|
/// Send a pong frame
pub async fn ServerConnection::pong(
  self : ServerConnection,
  data? : Bytes = Bytes::new(0),
) -> Unit {
  guard not(self.closed) else { raise ConnectionClosed }
  write_frame(self.conn, true, OpCode::Pong, data, false)
}

///|
/// Send a close frame with optional close code and reason
pub async fn ServerConnection::send_close(
  self : ServerConnection,
  code? : CloseCode = Normal,
  reason? : String = "",
) -> Unit {
  guard not(self.closed) else { return }
  let payload_size = 2 + reason.length()
  let payload = FixedArray::make(payload_size, b'\x00')

  // Encode close code
  let code_int = code.to_int()
  payload[0] = ((code_int >> 8) & 0xFF).to_byte()
  payload[1] = (code_int & 0xFF).to_byte()

  // Encode reason
  if reason != "" {
    let reason_bytes = @encoding/utf8.encode(reason)
    let reason_arr = reason_bytes.to_fixedarray()
    for i = 0; i < reason_arr.length(); i = i + 1 {
      payload[2 + i] = reason_arr[i]
    }
  }
  write_frame(
    self.conn,
    true,
    OpCode::Close,
    payload.unsafe_reinterpret_as_bytes(),
    false,
  )
  self.closed = true
}

///|
/// Receive a message from the WebSocket
/// Returns the complete message after assembling all frames
pub async fn ServerConnection::receive(self : ServerConnection) -> Message {
  guard not(self.closed) else { raise ConnectionClosed }
  let frames : Array[Frame] = []
  let mut first_opcode : OpCode? = None
  for {
    let frame = read_frame(self.conn)

    // Handle control frames immediately
    match frame.opcode {
      OpCode::Close => {
        // Echo close frame
        self.send_close()
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

///|
/// Create and run a WebSocket server
///
/// `addr` - The address to bind the server to
/// `path` - The WebSocket path to accept connections on (e.g., "/ws")
/// `f` - Callback function to handle each WebSocket connection
/// `allow_failure` - Whether to silently ignore failures in the callback
/// `max_connections` - Maximum number of concurrent connections
///
/// Example:
/// ```moonbit no-check
/// run_server(
///   @socket.Addr::parse("0.0.0.0:8080"),
///   "/ws",
///   async fn(ws, _addr) raise {
///     let msg = ws.receive()
///     match msg.mtype {
///       Text => {
///         let text = @encoding/utf8.decode(msg.data)
///         ws.send_text("Echo: " + text)
///       }
///       Binary => ws.send_binary(msg.data)
///     }
///   }
/// )
/// ```
pub async fn run_server(
  addr : @socket.Addr,
  _path : String, // Currently unused in this simplified implementation
  f : async (ServerConnection, @socket.Addr) -> Unit,
  allow_failure? : Bool = true,
  max_connections? : Int,
) -> Unit {
  let server = @socket.TcpServer::new(addr)
  match max_connections {
    Some(max_conn) =>
      server.run_forever(
        async fn(tcp_conn, client_addr) {
          // Try to perform WebSocket handshake
          if ServerConnection::handshake(tcp_conn) is Some(ws_conn) {
            f(ws_conn, client_addr)
          } else {
            // Not a valid WebSocket request, close connection
            tcp_conn.close()
          }
        },
        allow_failure~,
        max_connections=max_conn,
      )
    None =>
      server.run_forever(
        async fn(tcp_conn, client_addr) {
          // Try to perform WebSocket handshake
          if ServerConnection::handshake(tcp_conn) is Some(ws_conn) {
            f(ws_conn, client_addr)
          } else {
            // Not a valid WebSocket request, close connection
            tcp_conn.close()
          }
        },
        allow_failure~,
      )
  }
}
