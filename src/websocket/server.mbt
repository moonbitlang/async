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
struct ServerConnection {
  conn : @socket.Tcp
  mut closed : CloseCode?
}

///|
/// Handle WebSocket handshake on raw TCP connection - internal use
/// This performs the full HTTP upgrade handshake
async fn ServerConnection::handshake(conn : @socket.Tcp) -> ServerConnection? {
  // Read HTTP request
  let reader = @io.BufferedReader::new(conn)

  // Read request line
  let request_line = match reader.read_line() {
    Some(line) => line[:-1] // Remove trailing \r
    None => raise InvalidHandshake("Empty request")
  }

  // Validate request line
  if not(request_line.contains("GET")) || not(request_line.contains("HTTP/1.1")) {
    raise InvalidHandshake("Invalid request line: must be GET with HTTP/1.1")
  }

  // Read and parse headers
  let headers : Map[String, String] = {}
  while reader.read_line() is Some(line) {
    // Empty line marks end of headers
    if line.is_blank() {
      break
    }
    let line = line[:-1] // Remove trailing \r

    // Parse header line
    if line.contains(":") {
      let parts = line.split(":").to_array()
      if parts.length() >= 2 {
        let key = parts[0].trim(chars=" \t").to_string().to_lower()
        // Join remaining parts in case the value contains colons
        let value_parts = parts[1:]
        let value = if value_parts.length() == 1 {
          value_parts[0].trim(chars=" \t").to_string()
        } else {
          value_parts.join(":").trim(chars=" \t").to_string()
        }
        // Handle multi-value headers by taking the first value
        if not(headers.contains(key)) {
          headers[key] = value
        }
      }
    }
  }

  // Validate WebSocket handshake headers
  guard headers.get("upgrade") is Some(upgrade) &&
    upgrade.to_lower() == "websocket" else {
    raise InvalidHandshake("Missing or invalid Upgrade header")
  }
  guard headers.get("connection") is Some(connection) &&
    connection.to_lower().contains("upgrade") else {
    raise InvalidHandshake("Missing or invalid Connection header")
  }
  guard headers.get("sec-websocket-version") is Some(version) && version == "13" else {
    raise InvalidHandshake("Missing or unsupported WebSocket version")
  }
  guard headers.get("sec-websocket-key") is Some(key) else {
    raise InvalidHandshake("Missing Sec-WebSocket-Key header")
  }

  // Generate accept key
  let accept_key = generate_accept_key(key)

  // Send upgrade response
  let response =
    $|HTTP/1.1 101 Switching Protocols\r
    $|Upgrade: websocket\r
    $|Connection: Upgrade\r
    $|Sec-WebSocket-Accept: \{accept_key}\r
    $|\r
    $|
  conn.write(@encoding/utf8.encode(response))
  Some({ conn, closed: None })
}

///|
/// Close the WebSocket connection
pub fn ServerConnection::close(self : ServerConnection) -> Unit {
  if self.closed is None {
    self.conn.close()
    self.closed = Some(Normal)
  }
}

///|
/// Send a text message
pub async fn ServerConnection::send_text(
  self : ServerConnection,
  text : String,
) -> Unit {
  if self.closed is Some(code) {
    raise ConnectionClosed(code)
  }
  let payload = @encoding/utf8.encode(text)
  write_frame(self.conn, true, OpCode::Text, payload, false)
}

///|
/// Send a binary message
pub async fn ServerConnection::send_binary(
  self : ServerConnection,
  data : Bytes,
) -> Unit {
  if self.closed is Some(code) {
    raise ConnectionClosed(code)
  }
  write_frame(self.conn, true, OpCode::Binary, data, false)
}

///|
/// Send a ping frame
pub async fn ServerConnection::ping(
  self : ServerConnection,
  data? : Bytes = Bytes::new(0),
) -> Unit {
  if self.closed is Some(code) {
    raise ConnectionClosed(code)
  }
  write_frame(self.conn, true, OpCode::Ping, data, false)
}

///|
/// Send a pong frame
pub async fn ServerConnection::pong(
  self : ServerConnection,
  data? : Bytes = Bytes::new(0),
) -> Unit {
  if self.closed is Some(code) {
    raise ConnectionClosed(code)
  }
  write_frame(self.conn, true, OpCode::Pong, data, false)
}

///|
/// Send a close frame with optional close code and reason
pub async fn ServerConnection::send_close(
  self : ServerConnection,
  code? : CloseCode = Normal,
  reason? : BytesView = "",
) -> Unit {
  if self.closed is Some(c) {
    raise ConnectionClosed(c)
  }
  let payload_size = 2 + reason.length()
  let payload = FixedArray::make(payload_size, b'\x00')

  // Encode close code
  let code_int = code.to_int()
  payload[0] = ((code_int >> 8) & 0xFF).to_byte()
  payload[1] = (code_int & 0xFF).to_byte()

  // Encode reason
  if reason != "" {
    payload.blit_from_bytesview(2, reason)
  }
  write_frame(
    self.conn,
    true,
    OpCode::Close,
    payload.unsafe_reinterpret_as_bytes(),
    false,
  )
  self.closed = Some(code)
}

///|
/// Receive a message from the WebSocket
/// Returns the complete message after assembling all frames
pub async fn ServerConnection::receive(self : ServerConnection) -> Message {
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
          if frame.payload.length() > 2 {
            // As per spec https://datatracker.ietf.org/doc/html/rfc6455#autoid-27
            // The data is not guaranteed to be human readable
            // So we do not decode it here
            // And we are not using it further
            let _reason_bytes = payload_arr.unsafe_reinterpret_as_bytes()[2:]

          }
        }
        // If we didn't send close first, respond with close
        if self.closed is None {
          // Echo the close frame back and close
          self.send_close(code=close_code)
          self.closed = Some(close_code)
        }
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
  } // Default to binary
}

///|
/// Create and run a WebSocket server
///
/// - `addr` The address to bind the server to
/// - `path` The WebSocket path to accept connections on (e.g., "/ws")
/// - `f` Callback function to handle each WebSocket connection
/// - `allow_failure` Whether to silently ignore failures in the callback
/// - `max_connections` Maximum number of concurrent connections
///
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
          try {
            let ws_conn = ServerConnection::handshake(tcp_conn)
            match ws_conn {
              Some(conn) => f(conn, client_addr)
              None => tcp_conn.close()
            }
          } catch {
            InvalidHandshake(_) => {
              // Send proper HTTP error response before closing
              let error_response = "HTTP/1.1 400 Bad Request\r\n" +
                "Content-Length: 0\r\n" +
                "\r\n"
              tcp_conn.write(@encoding/utf8.encode(error_response))
              tcp_conn.close()
            }
            err => {
              tcp_conn.close()
              raise err
            }
          }
        },
        allow_failure~,
        max_connections=max_conn,
      )
    None =>
      server.run_forever(
        async fn(tcp_conn, client_addr) {
          // Try to perform WebSocket handshake
          try {
            let ws_conn = ServerConnection::handshake(tcp_conn)
            match ws_conn {
              Some(conn) => f(conn, client_addr)
              None => tcp_conn.close()
            }
          } catch {
            InvalidHandshake(_) => {
              // Send proper HTTP error response before closing
              let error_response = "HTTP/1.1 400 Bad Request\r\n" +
                "Content-Length: 0\r\n" +
                "\r\n"
              tcp_conn.write(@encoding/utf8.encode(error_response))
              tcp_conn.close()
            }
            err => {
              tcp_conn.close()
              raise err
            }
          }
        },
        allow_failure~,
      )
  }
}
