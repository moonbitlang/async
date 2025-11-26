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
  rand : @random.Rand
  mut closed : WebSocketError?
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
/// 
pub async fn Client::connect(
  host : String,
  path : String,
  port? : Int = 80,
  headers? : Map[String, String] = {},
) -> Client {
  // Ref : https://datatracker.ietf.org/doc/html/rfc6455#section-4.1
  let seed = FixedArray::make(32, b'\x00')
  if @tls.rand_bytes(seed, 32) != 1 {
    fail("Failed to get random bytes for WebSocket client")
  }
  let rand = @random.Rand::chacha8(seed=seed.unsafe_reinterpret_as_bytes())
  // Connect TCP socket
  let addr = @socket.Addr::parse("\{host}:\{port}")
  let conn = @socket.Tcp::connect(addr)

  // Send WebSocket handshake request
  let nonce = FixedArray::make(16, b'\x00')
  nonce.unsafe_write_uint32_le(0, rand.uint())
  nonce.unsafe_write_uint32_le(4, rand.uint())
  nonce.unsafe_write_uint32_le(8, rand.uint())
  nonce.unsafe_write_uint32_le(12, rand.uint())
  let key = base64_encode(nonce.unsafe_reinterpret_as_bytes())
  let request = "GET \{path} HTTP/1.1\r\n"
  conn.write(request)
  let host_header = if port == 80 || port == 443 {
    host
  } else {
    "\{host}:\{port}"
  }
  conn.write("Host: \{host_header}\r\n")
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
  let reader = conn
  guard reader.read_until("\r\n") is Some(response_line) else {
    conn.close()
    raise InvalidHandshake("Server closed connection during handshake")
  }
  guard response_line.contains("101") &&
    response_line.contains("Switching Protocols") else {
    conn.close()
    raise InvalidHandshake(
      "Server did not respond with 101 Switching Protocols: \{response_line}",
    )
  }
  let headers : Map[String, String] = {}
  while reader.read_until("\r\n") is Some(line) {
    if line.is_blank() {
      break
    }

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
  guard headers.get("sec-websocket-accept") is Some(accept_key) else {
    raise InvalidHandshake("Missing Sec-WebSocket-Accept header")
  }
  let expected_accept_key = generate_accept_key(key)
  guard accept_key.trim(chars=" \t\r") == expected_accept_key else {
    raise InvalidHandshake(
      "Invalid Sec-WebSocket-Accept value: \{accept_key} != \{expected_accept_key}",
    )
  }
  { conn, closed: None, rand }
}

///|
/// Close the WebSocket connection
pub fn Client::close(self : Client) -> Unit {
  if self.closed is None {
    self.conn.close()
    self.closed = Some(ConnectionClosed(Normal, None))
  }
}

///|
pub async fn Client::send_close(
  self : Client,
  code? : CloseCode = Normal,
  reason? : String,
) -> Unit {
  if self.closed is Some(e) {
    raise e
  }
  let code_int = code.to_int()
  let reason_bytes = @encoding/utf8.encode(reason.unwrap_or(""))
  if reason_bytes.length() > 123 {
    // Close reason too long
    // TODO: should we close the connection anyway?
    fail("Close reason too long")
  }
  let payload = FixedArray::make(2 + reason_bytes.length(), b'\x00')
  payload.unsafe_write_uint16_be(0, code_int.to_uint16())
  payload.blit_from_bytesview(2, reason_bytes)
  write_frame(
    self.conn,
    true,
    OpCode::Close,
    payload.unsafe_reinterpret_as_bytes(),
    @buffer.new()..write_int_le(self.rand.int()).to_bytes(),
  )
  // Wait until the server acknowledges the close
  ignore(read_frame(self.conn)) catch {
    _ => ()
  }
  self.closed = Some(ConnectionClosed(code, reason))
}

///|
/// Send a text message
pub async fn Client::send_text(self : Client, text : StringView) -> Unit {
  if self.closed is Some(code) {
    raise code
  }
  let payload = @encoding/utf8.encode(text)
  write_frame(
    self.conn,
    true,
    OpCode::Text,
    payload,
    @buffer.new()..write_int_le(self.rand.int()).to_bytes(),
  )
}

///|
/// Send a binary message
pub async fn Client::send_binary(self : Client, data : BytesView) -> Unit {
  if self.closed is Some(code) {
    raise code
  }
  write_frame(
    self.conn,
    true,
    OpCode::Binary,
    data,
    @buffer.new()..write_int_le(self.rand.int()).to_bytes(),
  )
}

///|
/// Send a ping frame
/// 
/// TODO : it should be able to return a boolean 
/// indicating if a pong was received within a timeout
async fn Client::_ping(self : Client, data? : Bytes = Bytes::new(0)) -> Unit {
  if self.closed is Some(code) {
    raise code
  }
  write_frame(
    self.conn,
    true,
    OpCode::Ping,
    data,
    @buffer.new()..write_int_le(self.rand.int()).to_bytes(),
  )
}

///|
/// Send a pong frame
/// 
/// This is done automatically, so it is not exposed in the public API
async fn Client::pong(self : Client, data? : Bytes = Bytes::new(0)) -> Unit {
  if self.closed is Some(code) {
    raise code
  }
  write_frame(
    self.conn,
    true,
    OpCode::Pong,
    data,
    @buffer.new()..write_int_le(self.rand.int()).to_bytes(),
  )
}

///|
/// Receive a message from the WebSocket
/// Returns the complete message after assembling all frames
pub async fn Client::receive(self : Client) -> Message {
  if self.closed is Some(code) {
    raise code
  }
  let frames : Array[Frame] = []
  let mut first_opcode : OpCode? = None
  while self.closed is None {
    let frame = read_frame(self.conn)

    // Handle control frames immediately
    match frame.opcode {
      Close => {
        // Parse close code and reason
        // Ref: https://datatracker.ietf.org/doc/html/rfc6455#section-5.5.1
        let mut close_code = Normal
        let mut reason : String? = None
        if frame.payload is [u16be(code), .. rest] {
          close_code = CloseCode::from_int(code.reinterpret_as_int())
          reason = Some(@encoding/utf8.decode(rest)) catch {
            _ => {
              // Invalid reason, fail fast
              close_code = ProtocolError
              None
            }
          }
        } else {
          guard frame.payload is [] else {
            // Invalid close payload
            close_code = ProtocolError
          }
        }
        // If we didn't send close first, respond with close
        if self.closed is None {
          // Echo the close frame back and close
          self.send_close(code=close_code, reason?) catch {
            _ => ()
          }
        }
        continue
      }
      Ping =>
        // Auto-respond to ping with pong
        self.pong(data=frame.payload)
      Pong =>
        // Ignore pong frames
        ()
      Text =>
        if first_opcode is Some(_) {
          // Ref https://datatracker.ietf.org/doc/html/rfc6455#section-5.4
          // We don't have extensions, so fragments MUST NOT be interleaved
          self.send_close(code=ProtocolError) catch {
            _ => ()
          }
        } else if frame.fin {
          // Single-frame text message
          return Message::Text(@encoding/utf8.decode(frame.payload)) catch {
            _ => {
              // Ref https://datatracker.ietf.org/doc/html/rfc6455#section-8.1
              // We MUST Fail the WebSocket Connection if the payload is not
              // valid UTF-8
              self.send_close(code=InvalidFramePayload) catch {
                _ => ()
              }
              continue
            }
          }
        } else {
          first_opcode = Some(Text)
          // Start of fragmented text message
          frames.push(frame)
        }
      Binary =>
        if first_opcode is Some(_) {
          // Ref https://datatracker.ietf.org/doc/html/rfc6455#section-5.4
          // We don't have extensions, so fragments MUST NOT be interleaved
          self.send_close(code=ProtocolError) catch {
            _ => ()
          }
        } else if frame.fin {
          // Single-frame binary message
          return Message::Binary(frame.payload)
        } else {
          first_opcode = Some(Binary)
          frames.push(frame)
        }
      Continuation => {
        if first_opcode is None {
          // Continuation frame without a starting frame
          self.send_close(code=ProtocolError) catch {
            _ => ()
          }
          continue
        }
        frames.push(frame)
        if frame.fin {
          // Final fragment received, assemble message
          let total_size = frames.fold(init=0, fn(acc, f) {
            acc + f.payload.length()
          })
          let data = FixedArray::make(total_size, b'\x00')
          let mut offset = 0
          for f in frames {
            data.blit_from_bytes(offset, f.payload, 0, f.payload.length())
            offset += f.payload.length()
          }
          let message_data = data.unsafe_reinterpret_as_bytes()
          match first_opcode {
            Some(Text) => {
              let text = @encoding/utf8.decode(message_data) catch {
                _ => {
                  self.send_close(code=InvalidFramePayload) catch {
                    _ => ()
                  }
                  continue
                }
              }
              return Message::Text(text)
            }
            Some(Binary) => return Message::Binary(message_data)
            _ => panic()
          }
          // Reset for next message
          frames.clear()
          first_opcode = None
        }
      }
    }
  }
  raise self.closed.unwrap()
}
