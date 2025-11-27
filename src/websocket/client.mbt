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
  conn : @http.Client
  rand : @random.Rand
  mut closed : WebSocketError?
}

///|
/// Create a WebSocket client from an existing HTTP client.
/// The HTTP client must be in a clean state (i.e. not in the middle of a request).
/// A WebSocket handshake will be sent to `path` via the HTTP client.
/// If the handshake succeeds, a WebSocket tunnel will be established and returned.
///
/// The ownership of the HTTP client will be transferred to this function.
/// So caller must not use the client anymore, nor close it.
///
/// Extra headers during the WebSocket handshake can be specified via `extra_headers`.
/// Some headers are reserved for the WebSocket protocol
/// and must NOT be set in `extra_headers`:
///
/// - those headers set by `@http.Client`, see `@http.Client::new`
/// - `Connection`, `Upgrade`
/// - `Sec-WebSocket-Key`, `Sec-WebSocket,Version`
pub async fn Client::from_http(
  conn : @http.Client,
  path : String,
  extra_headers? : Map[String, String] = {},
) -> Client {
  // Ref : https://datatracker.ietf.org/doc/html/rfc6455#section-4.1
  let seed = FixedArray::make(32, b'\x00')
  if @tls.rand_bytes(seed, 32) != 1 {
    fail("Failed to get random bytes for WebSocket client")
  }
  let rand = @random.Rand::chacha8(seed=seed.unsafe_reinterpret_as_bytes())

  // Send WebSocket handshake request
  let nonce = FixedArray::make(16, b'\x00')
  nonce.unsafe_write_uint32_le(0, rand.uint())
  nonce.unsafe_write_uint32_le(4, rand.uint())
  nonce.unsafe_write_uint32_le(8, rand.uint())
  nonce.unsafe_write_uint32_le(12, rand.uint())
  let key = base64_encode(nonce.unsafe_reinterpret_as_bytes())
  extra_headers["Connection"] = "Upgrade"
  extra_headers["Upgrade"] = "websocket"
  extra_headers["Sec-WebSocket-Key"] = key
  extra_headers["Sec-WebSocket-Version"] = "13"
  try {
    let response = conn..request(Get, path, extra_headers~).end_request()
    guard response.code is 101 else {
      raise InvalidHandshake(
        "Server did not respond with 101 Switching Protocols: \{response.code} \{response.reason}",
      )
    }

    // Validate WebSocket handshake headers
    guard response.headers.get("upgrade") is Some(upgrade) &&
      upgrade.to_lower() == "websocket" else {
      raise InvalidHandshake("Missing or invalid Upgrade header")
    }
    guard response.headers.get("connection") is Some(connection) &&
      connection.to_lower().contains("upgrade") else {
      raise InvalidHandshake("Missing or invalid Connection header")
    }
    guard response.headers.get("sec-websocket-accept") is Some(accept_key) else {
      raise InvalidHandshake("Missing Sec-WebSocket-Accept header")
    }
    let expected_accept_key = generate_accept_key(key)
    guard accept_key == expected_accept_key else {
      raise InvalidHandshake(
        "Invalid Sec-WebSocket-Accept value: \{accept_key} != \{expected_accept_key}",
      )
    }
    conn.enter_passthrough_mode()
    { conn, closed: None, rand }
  } catch {
    err => {
      conn.close()
      raise err
    }
  }
}

///|
/// Connect to a WebSocket server via the given URL.
/// The protocol of the URL must be either `ws` (for unencrypted WebSocket connection)
/// or `wss` (for TLS encrypted WebSocket connection).
///
/// Extra headers during the WebSocket handshake can be specified via `extra_headers`.
/// Some headers are reserved for the WebSocket protocol
/// and must NOT be set in `extra_headers`:
///
/// - those headers set by `@http.Client`, see `@http.Client::new`
/// - `Connection`, `Upgrade`
/// - `Sec-WebSocket-Key`, `Sec-WebSocket,Version`
///
/// If `proxy` is present, the websocket client will tunnel traffic through the proxy.
/// See `@http.Client::new` for more details.
///
/// Example:
/// ```moonbit no-check
/// let ws = Client::connect("ws://example.com/endpoint")
/// ```
/// 
pub async fn Client::connect(
  url : String,
  headers? : Map[String, String] = {},
  proxy? : @http.Client,
) -> Client {
  guard url.find("://") is Some(protocol_len) else {
    abort("`@websocket.Client::connect()`: invalid URL: missing protocol")
  }
  let http_protocol = match url[:protocol_len] {
    "ws" => "http"
    "wss" => "https"
    protocol =>
      abort("`@websocket.Client::connect()`: invalid protocol \{protocol}")
  }
  let url = url[protocol_len + 3:]
  let (host, path) = if url.find("/") is Some(i) {
    (url[:i].to_string(), url[i:].to_string())
  } else {
    (url.to_string(), "/")
  }
  let path = if path == "" { "/" } else { path }
  let conn = @http.Client::new("\{http_protocol}://\{host}", proxy?)
  Client::from_http(conn, path, extra_headers=headers)
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
          // 0-999 not used
          // 1000-2999 reserved for protocol
          if (close_code is Other(i) && i < 3000) || close_code is Abnormal {
            // Invalid close code
            close_code = ProtocolError
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
