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
  out : @async.Queue[Result[Message, Error]]
  semaphore : @semaphore.Semaphore
}

///|
/// Handle WebSocket handshake on raw TCP connection - internal use
/// This performs the full HTTP upgrade handshake
async fn ServerConnection::handshake(conn : @socket.Tcp) -> ServerConnection {
  // Read HTTP request
  let reader = conn

  // Read request line
  let request_line = match reader.read_until("\r\n") {
    Some(line) => line // Remove trailing \r
    None => raise InvalidHandshake("Empty request")
  }

  // Validate request line
  if not(request_line.contains("GET")) || not(request_line.contains("HTTP/1.1")) {
    raise InvalidHandshake("Invalid request line: must be GET with HTTP/1.1")
  }

  // Read and parse headers
  let headers : Map[String, String] = {}
  while reader.read_until("\r\n") is Some(line) {
    // Empty line marks end of headers
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
  {
    conn,
    closed: None,
    out: @aqueue.new(),
    semaphore: @semaphore.Semaphore::new(1),
  }
}

///|
/// The main read loop for the WebSocket connection
/// 
/// This does not raise any errors. Errors are communicated via the out queue.
async fn ServerConnection::serve_read(self : ServerConnection) -> Unit noraise {
  let frames : Array[Frame] = []
  let mut first_opcode : OpCode? = None
  while self.closed is None {
    let frame = read_frame(self.conn) catch {
      FrameError => {
        // On frame error, close the connection and communicate the error
        if self.closed is None {
          self.send_close(code=ProtocolError) catch {
            _ => ()
          }
        }
        self.out.put(Err(ConnectionClosed(ProtocolError)))
        return
      }
      e => {
        // On read error, close the connection and communicate the error
        if self.closed is None {
          self.closed = Some(Abnormal)
        }
        self.out.put(Err(e))
        return
      }
    }

    // Handle control frames immediately
    match frame.opcode {
      Close => {
        // Parse close code and reason
        // Ref: https://datatracker.ietf.org/doc/html/rfc6455#section-5.5.1
        let mut close_code = Normal
        if frame.payload is [u16be(code), ..] {
          close_code = CloseCode::from_int(code.reinterpret_as_int()) catch {
            FrameError =>
              // Invalid close code, use ProtocolError
              ProtocolError
          }
        }
        // If we didn't send close first, respond with close
        if self.closed is None {
          // Echo the close frame back and close
          self.send_close(code=close_code) catch {
            _ => ()
          }
          self.out.put(Err(ConnectionClosed(close_code)))
        }
        return
      }
      Ping => {
        if !frame.fin {
          // Control frames MUST NOT be fragmented
          self.send_close(code=ProtocolError) catch {
            _ => ()
          }
          self.out.put(Err(ConnectionClosed(ProtocolError)))
          return
        }
        // Auto-respond to ping with pong
        self.pong(data=frame.payload) catch {
          e => {
            if self.closed is None {
              self.closed = Some(Abnormal)
            }
            self.out.put(Err(e))
            return
          }
        }
      }
      Pong =>
        // Ignore pong frames
        // TODO : track pong responses for ping timeouts
        if !frame.fin {
          // Control frames MUST NOT be fragmented
          self.send_close(code=ProtocolError) catch {
            _ => ()
          }
          self.out.put(Err(ConnectionClosed(ProtocolError)))
          return
        }
      Text =>
        if first_opcode is Some(_) {
          // Ref https://datatracker.ietf.org/doc/html/rfc6455#section-5.4
          // We don't have extensions, so fragments MUST NOT be interleaved
          self.send_close(code=ProtocolError) catch {
            _ => ()
          }
          self.out.put(Err(ConnectionClosed(ProtocolError)))
          return
        } else if frame.fin {
          // Single-frame text message
          let text = @encoding/utf8.decode(frame.payload) catch {
            _ => {
              // Ref https://datatracker.ietf.org/doc/html/rfc6455#section-8.1
              // We MUST Fail the WebSocket Connection if the payload is not
              // valid UTF-8
              self.send_close(code=InvalidFramePayload) catch {
                _ => ()
              }
              self.out.put(Err(ConnectionClosed(InvalidFramePayload)))
              return
            }
          }
          let message = Message::Text(text)
          // Handle the complete message
          self.out.put(Ok(message))
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
          self.out.put(Err(ConnectionClosed(ProtocolError)))
          return
        } else if frame.fin {
          // Single-frame binary message
          let message = Message::Binary(frame.payload)
          // Handle the complete message
          self.out.put(Ok(message))
        } else {
          first_opcode = Some(Binary)
          // Start of fragmented binary message
          frames.push(frame)
        }
      Continuation => {
        if first_opcode is None {
          // Continuation frame without a starting frame
          self.send_close(code=ProtocolError) catch {
            _ => ()
          }
          self.out.put(Err(ConnectionClosed(ProtocolError)))
          return
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
                  self.out.put(Err(ConnectionClosed(InvalidFramePayload)))
                  return
                }
              }
              let message = Message::Text(text)
              self.out.put(Ok(message))
            }
            Some(Binary) => {
              let message = Message::Binary(message_data)
              self.out.put(Ok(message))
            }
            _ => panic()
          }
          // Reset for next message
          frames.clear()
          first_opcode = None
        }
      }
    }
  }
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
  text : StringView,
) -> Unit {
  if self.closed is Some(code) {
    raise ConnectionClosed(code)
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
    raise ConnectionClosed(code)
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
    raise ConnectionClosed(code)
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
    raise ConnectionClosed(code)
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
  self.closed = Some(code)
}

///|
/// Receive a message from the WebSocket
/// Returns the complete message after assembling all frames
pub async fn ServerConnection::receive(self : ServerConnection) -> Message {
  if self.closed is Some(code) {
    raise ConnectionClosed(code)
  }
  self.out.get().unwrap_or_error()
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
  allow_failure? : Bool,
  max_connections? : Int,
) -> Unit {
  let server = @socket.TcpServer::new(addr)
  server.run_forever(
    async fn(tcp_conn, client_addr) {
      let ws_conn = ServerConnection::handshake(tcp_conn) catch {
        // Per spec section 4.2.1 of RFC 6455, send 400 Bad Request on failure
        InvalidHandshake(_) as e => {
          // Send proper HTTP error response before closing
          let error_response = "HTTP/1.1 400 Bad Request\r\n" +
            "Content-Length: 0\r\n" +
            "\r\n"
          tcp_conn.write(@encoding/utf8.encode(error_response))
          raise e
        }
        // Handle other unexpected errors
        e => {
          let error_response = "HTTP/1.1 500 Internal Server Error\r\n" +
            "Content-Length: 0\r\n" +
            "\r\n"
          tcp_conn.write(@encoding/utf8.encode(error_response))
          raise e
        }
      }
      @async.with_task_group(taskgroup => {
        taskgroup.spawn_bg(() => f(ws_conn, client_addr))
        taskgroup.spawn_bg(() => ws_conn.serve_read())
      })
    },
    allow_failure?,
    max_connections?,
  )
}
