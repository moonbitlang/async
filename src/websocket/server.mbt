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
  conn : @http.ServerConnection
  mut closed : WebSocketError?
  semaphore : @semaphore.Semaphore
}

///|
/// Handle a WebSocket handshake request
/// and convert an existing HTTP server connection to a WebSocket connection.
///
/// - `request`: the WebSocket handshake request
/// - `conn`: the HTTP server connection
///
/// If the handshake succeeds, a new WebSocket tunnel will be created and returned.
///
/// The ownership of `conn` will be transferred to
/// `@websocket.ServerConnection::from_http`,
/// so the user must NOT use or close the HTTP server connection anymore.
pub async fn ServerConnection::from_http(
  request : @http.Request,
  conn : @http.ServerConnection,
) -> ServerConnection {
  try {
    async fn bad_request(msg : String) {
      conn..send_response(400, "Bad Request")..write(msg)..end_response()
      raise InvalidHandshake(msg)
    }

    guard request.meth is Get else {
      bad_request("Invalid request: must be GET")
    }

    // Validate WebSocket handshake headers
    guard request.headers.get("upgrade") is Some(upgrade) &&
      upgrade.to_lower() == "websocket" else {
      bad_request("Missing or invalid Upgrade header")
    }
    guard request.headers.get("connection") is Some(connection) &&
      connection.to_lower().contains("upgrade") else {
      bad_request("Missing or invalid Connection header")
    }
    guard request.headers.get("sec-websocket-version") is Some(version) &&
      version == "13" else {
      bad_request("Missing or unsupported WebSocket version")
    }
    guard request.headers.get("sec-websocket-key") is Some(key) else {
      bad_request("Missing Sec-WebSocket-Key header")
    }

    // Generate accept key
    let accept_key = generate_accept_key(key)
    conn
    ..send_response(101, "Switching Protocols", extra_headers={
      "Upgrade": "websocket",
      "Connection": "Upgrade",
      "Sec-WebSocket-Accept": accept_key,
    })
    ..end_response()
    ..enter_passthrough_mode()
    { conn, closed: None, semaphore: @semaphore.Semaphore::new(1) }
  } catch {
    err => {
      conn.close()
      raise err
    }
  }
}

///|
async fn ServerConnection::read_frame(self : ServerConnection) -> Frame {
  read_frame(self.conn) catch {
    err => {
      if err is FrameError {
        // On frame error, close the connection and communicate the error
        self.send_close(code=ProtocolError)
      }
      raise err
    }
  }
}

///|
/// The main read loop for the WebSocket connection
/// 
/// This does not raise any errors. Errors are communicated via the out queue.
pub async fn ServerConnection::receive(self : ServerConnection) -> Message {
  let frames : Array[Frame] = []
  let first_frame = self.read_frame()
  let mut first_opcode = None

  // Handle control frames immediately
  loop first_frame {
    { opcode: Close, payload, .. } => {
      // Parse close code and reason
      // Ref: https://datatracker.ietf.org/doc/html/rfc6455#section-5.5.1
      let mut close_code = Normal
      let mut reason = None
      if payload is [u16be(code), .. rest] {
        close_code = CloseCode::from_int(code.reinterpret_as_int())
        reason = Some(@encoding/utf8.decode(rest)) catch {
          err => {
            // Invalid reason, fail fast
            if self.closed is None {
              self.send_close(code=close_code)
            }
            raise err
          }
        }
        // 0-999 not used
        // 1000-2999 reserved for protocol
        if (close_code is Other(i) && i < 3000) || close_code is Abnormal {
          // Invalid close code
          close_code = ProtocolError
        }
      } else if not(payload is []) {
        close_code = ProtocolError
      }
      // If we didn't send close first, respond with close
      if self.closed is Some(err) {
        raise err
      }
      let err = ConnectionClosed(close_code, reason)
      // Echo the close frame back and close
      defer {
        self.closed = Some(err)
      }
      self.send_close(code=close_code, reason?)
      raise err
    }
    { opcode: Ping | Pong, fin: false, .. } => {
      // Control frames MUST NOT be fragmented
      self.send_close(code=ProtocolError)
      raise WebSocketError::ProtocolError
    }
    { opcode: Ping, payload, .. } => {
      // Auto-respond to ping with pong
      {
        self.semaphore.acquire()
        defer self.semaphore.release()
        self.pong(data=payload)
      }
      continue self.read_frame()
    }
    { opcode: Pong, .. } =>
      // Ignore pong frames
      // TODO : track pong responses for ping timeouts
      continue self.read_frame()
    { opcode: Text | Binary, .. } if first_opcode is Some(_) => {
      // Ref https://datatracker.ietf.org/doc/html/rfc6455#section-5.4
      // We don't have extensions, so fragments MUST NOT be interleaved
      self.send_close(code=ProtocolError)
      raise WebSocketError::ProtocolError
    }
    { opcode: Text | Binary as opcode, fin: false, .. } as frame => {
      first_opcode = Some(opcode)
      // Start of fragmented text message
      frames.push(frame)
      continue self.read_frame()
    }
    { opcode: Text, fin: true, payload } => {
      // Single-frame text message
      let text = @encoding/utf8.decode(payload) catch {
        err => {
          // Ref https://datatracker.ietf.org/doc/html/rfc6455#section-8.1
          // We MUST Fail the WebSocket Connection if the payload is not
          // valid UTF-8
          self.send_close(code=InvalidFramePayload)
          raise err
        }
      }
      let message = Message::Text(text)
      // Handle the complete message
      message
    }
    { opcode: Binary, fin: true, payload } => {
      // Single-frame binary message
      let message = Message::Binary(payload)
      // Handle the complete message
      message
    }
    { opcode: Continuation, .. } if first_opcode is None => {
      // Continuation frame without a starting frame
      self.send_close(code=ProtocolError)
      raise WebSocketError::ProtocolError
    }
    { opcode: Continuation, fin: false, .. } as frame => {
      frames.push(frame)
      continue self.read_frame()
    }
    { opcode: Continuation, fin: true, .. } as frame => {
      frames.push(frame)
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
            err => {
              self.send_close(code=InvalidFramePayload)
              raise err
            }
          }
          let message = Message::Text(text)
          message
        }
        Some(Binary) => {
          let message = Message::Binary(message_data)
          message
        }
        _ => panic()
      }
    }
  }
}

///|
/// Close the WebSocket connection
pub fn ServerConnection::close(self : ServerConnection) -> Unit {
  if self.closed is None {
    self.conn.close()
    self.closed = Some(ConnectionClosed(Normal, None))
  }
}

///|
/// Send a text message
pub async fn ServerConnection::send_text(
  self : ServerConnection,
  text : StringView,
) -> Unit {
  if self.closed is Some(code) {
    raise code
  }
  self.semaphore.acquire()
  defer self.semaphore.release()
  let payload = @encoding/utf8.encode(text)
  write_frame(self.conn, true, OpCode::Text, payload, [])
}

///|
/// Send a binary message
pub async fn ServerConnection::send_binary(
  self : ServerConnection,
  data : BytesView,
) -> Unit {
  if self.closed is Some(code) {
    raise code
  }
  self.semaphore.acquire()
  defer self.semaphore.release()
  write_frame(self.conn, true, OpCode::Binary, data, [])
}

///|
/// Send a ping frame
/// 
/// TODO : it should be able to return a boolean 
/// indicating if a pong was received within a timeout
async fn ServerConnection::_ping(
  self : ServerConnection,
  data? : Bytes = Bytes::new(0),
) -> Unit {
  if self.closed is Some(code) {
    raise code
  }
  self.semaphore.acquire()
  defer self.semaphore.release()
  write_frame(self.conn, true, OpCode::Ping, data, [])
}

///|
/// Send a pong frame
/// 
/// It is done automatically, so it is not exposed in the public API
async fn ServerConnection::pong(
  self : ServerConnection,
  data? : Bytes = Bytes::new(0),
) -> Unit {
  if self.closed is Some(code) {
    raise code
  }
  self.semaphore.acquire()
  defer self.semaphore.release()
  write_frame(self.conn, true, OpCode::Pong, data, [])
}

///|
/// Send a close frame with optional close code and reason
pub async fn ServerConnection::send_close(
  self : ServerConnection,
  code? : CloseCode = Normal,
  reason? : String = "",
) -> Unit {
  if self.closed is Some(code) {
    raise code
  }
  let reason_data = @encoding/utf8.encode(reason)
  if reason_data.length() > 123 {
    // Close reason too long
    // TODO: should we close the connection anyway?
    fail("Close reason too long")
  }
  let payload_size = 2 + reason_data.length()
  let payload = FixedArray::make(payload_size, b'\x00')

  // Encode close code
  let code_int = code.to_int()
  payload[0] = ((code_int >> 8) & 0xFF).to_byte()
  payload[1] = (code_int & 0xFF).to_byte()

  // Encode reason
  if reason_data != "" {
    payload.blit_from_bytesview(2, reason_data)
  }
  self.semaphore.acquire()
  defer self.semaphore.release()
  write_frame(
    self.conn,
    true,
    OpCode::Close,
    payload.unsafe_reinterpret_as_bytes(),
    [],
  )
  // Set closed status AFTER the frame has been written
  // This ensures the frame is sent before any connection cleanup
  self.closed = Some(ConnectionClosed(code, Some(reason)))
}
