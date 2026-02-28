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
/// HTTP/2 server connection.
/// Wraps an H2Connection with server-specific behavior.
pub struct H2ServerConnection {
  conn : H2Connection
}

///|
/// Create a new HTTP/2 server connection.
/// Reads and verifies the client preface magic,
/// reads client SETTINGS, sends server SETTINGS,
/// sends SETTINGS ACK, and spawns the background read loop.
pub async fn[R : @io.Reader, W : @io.Writer] H2ServerConnection::new(
  r : R,
  w : W,
) -> H2ServerConnection {
  let conn = H2Connection::new(r, w, is_client=false)
  // Disable server push
  conn.local_settings.enable_push = false
  // Read and verify client preface magic (24 bytes)
  let magic = conn.reader.read_exactly(client_preface.length())
  if magic != client_preface {
    raise H2Error(ProtocolError, "invalid client preface")
  }
  // Read client's SETTINGS
  let frame = read_frame(conn.reader)
  guard frame.header.frame_type is Settings else {
    raise H2Error(
      ProtocolError,
      "expected SETTINGS frame after preface, got \{frame.header.frame_type}",
    )
  }
  conn.remote_settings.apply(frame.payload)
  // Send server SETTINGS
  conn.send_settings()
  // Send SETTINGS ACK for client's settings
  conn.send_settings_ack()
  // Update send window based on remote settings
  let window_diff = conn.remote_settings.initial_window_size -
    default_initial_window_size
  if window_diff != 0 {
    conn.send_window.update(window_diff)
  }
  H2ServerConnection::{ conn, }
}

///|
/// Start the background read loop for this server connection.
pub async fn H2ServerConnection::run_read_loop(
  self : H2ServerConnection,
) -> Unit {
  self.conn.read_loop()
}

///|
/// Accept the next incoming stream from a client.
/// Blocks until a new stream with headers arrives.
pub async fn H2ServerConnection::accept_stream(
  self : H2ServerConnection,
) -> H2Stream {
  self.conn.incoming_streams.get()
}

///|
/// Send response headers on a stream.
pub async fn H2ServerConnection::send_response(
  self : H2ServerConnection,
  stream : H2Stream,
  status : Int,
  headers? : Map[String, String] = {},
  end_stream? : Bool = false,
) -> Unit {
  let header_list : Array[(String, String)] = []
  header_list.push((":status", status.to_string()))
  for name, value in headers {
    header_list.push((name, value))
  }
  self.conn.send_headers(stream.id, header_list, end_stream~)
  if end_stream {
    stream.state = match stream.state {
      Open => HalfClosedLocal
      HalfClosedRemote => Closed
      _ => stream.state
    }
  }
}

///|
/// Send response data on a stream.
pub async fn H2ServerConnection::send_data(
  self : H2ServerConnection,
  stream : H2Stream,
  data : Bytes,
  end_stream? : Bool = false,
) -> Unit {
  ignore(self)
  stream.send_data(data, end_stream~)
  if end_stream {
    stream.state = match stream.state {
      Open => HalfClosedLocal
      HalfClosedRemote => Closed
      _ => stream.state
    }
  }
}

///|
/// Send trailing headers on a stream with END_STREAM.
/// Must be called after all DATA frames have been sent.
pub async fn H2ServerConnection::send_trailers(
  self : H2ServerConnection,
  stream : H2Stream,
  trailers : Map[String, String],
) -> Unit {
  ignore(self)
  stream.send_trailers(trailers)
}

///|
/// Close the HTTP/2 server connection gracefully.
pub async fn H2ServerConnection::close(self : H2ServerConnection) -> Unit {
  if not(self.conn.goaway_sent) {
    self.conn.send_goaway(NoError)
  }
  self.conn.closed = true
  self.conn.incoming_streams.close(clear=true)
}
