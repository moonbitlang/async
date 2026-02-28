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
/// A single HTTP/2 stream.
pub struct H2Stream {
  id : Int
  mut state : StreamState
  send_window : FlowWindow
  mut recv_window : Int
  inbound_data : @aqueue.Queue[Bytes]
  mut headers : Map[String, String]?
  headers_ready : @cond_var.Cond
  mut trailers : Map[String, String]?
  trailers_ready : @cond_var.Cond
  mut error : H2ErrorCode?
  conn : H2Connection
  read_buf : @io.ReaderBuffer
}

///|
/// Create a new stream.
fn H2Stream::new(
  id : Int,
  state : StreamState,
  initial_send_window : Int,
  initial_recv_window : Int,
  conn : H2Connection,
) -> H2Stream {
  {
    id,
    state,
    send_window: FlowWindow::new(initial_send_window),
    recv_window: initial_recv_window,
    inbound_data: @aqueue.Queue::new(kind=Blocking(64)),
    headers: None,
    headers_ready: @cond_var.Cond::new(),
    trailers: None,
    trailers_ready: @cond_var.Cond::new(),
    error: None,
    conn,
    read_buf: @io.ReaderBuffer::new(),
  }
}

///|
/// Get the stream ID.
pub fn H2Stream::stream_id(self : H2Stream) -> Int {
  self.id
}

///|
/// Get the stream error, if any.
pub fn H2Stream::get_error(self : H2Stream) -> H2ErrorCode? {
  self.error
}

///|
/// Wait for response headers to be available.
pub async fn H2Stream::wait_headers(self : H2Stream) -> Map[String, String] {
  while self.headers is None {
    if self.error is Some(code) {
      raise H2Error(code, "stream \{self.id} error")
    }
    self.headers_ready.wait()
  }
  // Check for error again after waking
  if self.error is Some(code) {
    raise H2Error(code, "stream \{self.id} error")
  }
  self.headers.unwrap()
}

///|
/// Wait for trailers to be available.
/// Trailers are HEADERS frames received after DATA frames (with END_STREAM).
/// Returns `None` if the stream ended without trailers.
pub async fn H2Stream::wait_trailers(self : H2Stream) -> Map[String, String]? {
  // Wait until the remote side is done sending (HalfClosedRemote or Closed)
  while self.trailers is None {
    if self.error is Some(code) {
      raise H2Error(code, "stream \{self.id} error")
    }
    if self.state is (HalfClosedRemote | Closed) {
      return None
    }
    self.trailers_ready.wait()
  }
  if self.error is Some(code) {
    raise H2Error(code, "stream \{self.id} error")
  }
  self.trailers
}

///|
/// Send trailing headers on this stream with END_STREAM.
/// Must be called after all DATA frames have been sent.
pub async fn H2Stream::send_trailers(
  self : H2Stream,
  trailers : Map[String, String],
) -> Unit {
  let header_list : Array[(String, String)] = []
  for name, value in trailers {
    header_list.push((name, value))
  }
  self.conn.send_headers(self.id, header_list, end_stream=true)
  self.state = match self.state {
    Open => HalfClosedLocal
    HalfClosedRemote => Closed
    _ => self.state
  }
}

///|
/// Read from the stream's inbound data queue.
/// Implements the Reader interface for consuming DATA payloads.
/// Sends WINDOW_UPDATE when recv window drops below threshold.
pub impl @io.Reader for H2Stream with _direct_read(self, buf, offset~, max_len~) {
  // Check for errors, but allow draining buffered data first
  if self.error is Some(code) {
    // If there's still buffered data, serve it before erroring
    match self.inbound_data.try_get() {
      Some(data) if data.length() > 0 => {
        let n = @cmp.minimum(data.length(), max_len)
        buf.blit_from_bytes(offset, data, 0, n)
        if n < data.length() {
          self.inbound_data.put(data[n:].to_bytes()) catch {
            _ => ()
          }
        }
        return n
      }
      _ => ()
    }
    // NoError means the stream was gracefully reset — treat as EOF
    if code is NoError {
      return 0
    }
    raise H2Error(code, "stream \{self.id} error")
  }
  let data = if self.state is (HalfClosedRemote | Closed) {
    match self.inbound_data.try_get() {
      Some(data) => data
      None => return 0
    }
  } else {
    self.inbound_data.get() catch {
      _ => return 0
    }
  }
  if data.length() == 0 {
    return 0
  }
  let n = @cmp.minimum(data.length(), max_len)
  buf.blit_from_bytes(offset, data, 0, n)
  // If we didn't consume all the data, put remainder back
  if n < data.length() {
    self.inbound_data.put(data[n:].to_bytes()) catch {
      _ => ()
    }
  }
  // Send WINDOW_UPDATE if recv window drops below half of initial
  self.recv_window = self.recv_window - n
  let threshold = default_initial_window_size / 2
  if self.recv_window < threshold {
    let increment = default_initial_window_size - self.recv_window
    self.recv_window = self.recv_window + increment
    // Send stream-level WINDOW_UPDATE
    self.conn.send_window_update(self.id, increment) catch {
      _ => ()
    }
  }
  n
}

///|
pub impl @io.Reader for H2Stream with _get_internal_buffer(self) {
  self.read_buf
}

///|
/// Send data on this stream, respecting flow control.
/// Fragments into max_frame_size chunks.
pub async fn H2Stream::send_data(
  self : H2Stream,
  data : Bytes,
  end_stream? : Bool = false,
) -> Unit {
  let mut offset = 0
  let remaining = data.length()
  while offset < remaining {
    let chunk_size = @cmp.minimum(
      remaining - offset,
      self.conn.remote_settings.max_frame_size,
    )
    // Consume from both stream-level and connection-level flow windows
    let allowed_stream = self.send_window.consume(chunk_size)
    let allowed_conn = self.conn.send_window.consume(allowed_stream)
    let send_size = allowed_conn
    let is_last = offset + send_size >= remaining && end_stream
    let flags = if is_last { flag_end_stream } else { b'\x00' }
    self.conn.locked_write_frame(
      Data,
      flags,
      self.id,
      data[offset:offset + send_size].to_bytes(),
    )
    offset = offset + send_size
  }
  if remaining == 0 && end_stream {
    self.conn.locked_write_frame(
      Data,
      flag_end_stream,
      self.id,
      Bytes::make(0, b'\x00'),
    )
  }
}
