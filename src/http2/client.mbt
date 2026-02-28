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
/// HTTP/2 client connection.
/// Wraps an H2Connection with client-specific behavior.
pub struct H2ClientConnection {
  conn : H2Connection
}

///|
/// Create a new HTTP/2 client connection.
/// Sends the client preface (magic + SETTINGS),
/// reads the server's SETTINGS, and sends SETTINGS ACK.
pub async fn[R : @io.Reader, W : @io.Writer] H2ClientConnection::new(
  r : R,
  w : W,
) -> H2ClientConnection {
  let conn = H2Connection::new(r, w, is_client=true)
  conn.local_settings.enable_push = false
  conn.writer.write(client_preface)
  conn.send_settings()
  let frame = read_frame(conn.reader)
  guard frame.header.frame_type is Settings else {
    raise H2Error(
      ProtocolError,
      "expected SETTINGS frame, got \{frame.header.frame_type}",
    )
  }
  conn.remote_settings.apply(frame.payload)
  conn.send_settings_ack()
  let window_diff = conn.remote_settings.initial_window_size -
    default_initial_window_size
  if window_diff != 0 {
    conn.send_window.update(window_diff)
  }
  H2ClientConnection::{ conn, }
}

///|
/// Start the background read loop for this client connection.
/// Must be called after new() to begin processing incoming frames.
/// Typically called inside a task group's spawn_bg.
pub async fn H2ClientConnection::run_read_loop(
  self : H2ClientConnection,
) -> Unit {
  self.conn.read_loop()
}

///|
/// Send a request on a new stream.
/// `meth` should be a method string like "GET", "POST", etc.
/// Returns the stream that can be used to read the response.
pub async fn H2ClientConnection::send_request(
  self : H2ClientConnection,
  meth : String,
  path : String,
  scheme? : String = "https",
  headers? : Map[String, String] = {},
  authority? : String = "",
) -> H2Stream {
  let stream = self.conn.alloc_stream()
  let header_list : Array[(String, String)] = []
  header_list.push((":method", meth))
  header_list.push((":path", path))
  header_list.push((":scheme", scheme))
  if authority.length() > 0 {
    header_list.push((":authority", authority))
  }
  for name, value in headers {
    header_list.push((name, value))
  }
  self.conn.send_headers(stream.id, header_list)
  stream
}

///|
/// Send a request with body on a new stream.
pub async fn H2ClientConnection::send_request_with_body(
  self : H2ClientConnection,
  meth : String,
  path : String,
  body : Bytes,
  scheme? : String = "https",
  headers? : Map[String, String] = {},
  authority? : String = "",
) -> H2Stream {
  let stream = self.conn.alloc_stream()
  let header_list : Array[(String, String)] = []
  header_list.push((":method", meth))
  header_list.push((":path", path))
  header_list.push((":scheme", scheme))
  if authority.length() > 0 {
    header_list.push((":authority", authority))
  }
  for name, value in headers {
    header_list.push((name, value))
  }
  let end_stream = body.length() == 0
  self.conn.send_headers(stream.id, header_list, end_stream~)
  if body.length() > 0 {
    stream.send_data(body, end_stream=true)
  }
  stream
}

///|
/// Close the HTTP/2 client connection gracefully.
pub async fn H2ClientConnection::close(self : H2ClientConnection) -> Unit {
  if not(self.conn.goaway_sent) {
    self.conn.send_goaway(NoError)
  }
  self.conn.closed = true
  self.conn.incoming_streams.close(clear=true)
}
